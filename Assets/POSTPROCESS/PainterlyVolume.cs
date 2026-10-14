using System;
using UnityEngine;
using UnityEngine.Rendering;

public enum PainterlyResolution
{
    Full = 1,
    Half = 2,
    Quarter = 4
}

[Serializable]
public sealed class PainterlyResolutionParameter : VolumeParameter<PainterlyResolution>
{
    public PainterlyResolutionParameter(PainterlyResolution value, bool overrideState = false)
        : base(value, overrideState) { }
}

/// <summary>
/// Add this to a Volume profile (Add Override > Post-processing > Painterly Brush).
/// </summary>
[Serializable]
[VolumeComponentMenu("Post-processing/Painterly Kuwahara")] // kept so existing profiles keep their override
public sealed class PainterlyVolume : VolumeComponent
{
    [Header("Master")]
    [Tooltip("Standalone Quest / mobile mode: one stroke layer, 3-tap bleed, flow map forced to Quarter res, at most 1 additional light repainted.")]
    public BoolParameter questMode = new BoolParameter(false);

    [Tooltip("0 = original image, 1 = full effect. The effect is skipped entirely at 0.")]
    public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);

    [Tooltip("Resolution of the small flow map that orients the strokes (and drives edge darkening). Quarter is plenty; strokes and canvas always render at full resolution.")]
    public PainterlyResolutionParameter resolution = new PainterlyResolutionParameter(PainterlyResolution.Quarter);

    [Tooltip("Interpret pixel sizes relative to the Reference Height so the look is identical at any resolution (recommended for VR / varying eye-buffer sizes).")]
    public BoolParameter scaleWithResolution = new BoolParameter(true);

    public MinFloatParameter referenceHeight = new MinFloatParameter(1080f, 144f);

    [Header("Brush strokes (brush atlas)")]
    public ClampedFloatParameter strokeStrength = new ClampedFloatParameter(0.8f, 0f, 1f);
    [Tooltip("Approximate stroke size in pixels (at Reference Height).")]
    public MinFloatParameter strokeSize = new MinFloatParameter(28f, 4f);
    [Tooltip("Fraction of a cell the stamp covers. Keep <= 0.95 to avoid visible cell borders.")]
    public ClampedFloatParameter strokeStamp = new ClampedFloatParameter(0.9f, 0.4f, 1f);
    [Tooltip("How much strokes thin out across the flow where edges are strong.")]
    public ClampedFloatParameter strokeElongation = new ClampedFloatParameter(1.8f, 1f, 4f);
    [Tooltip("1 = strokes follow the edges of the image. 0 = every stroke gets a fixed random angle per seed (rock solid, never rotates when you move). Lower this for very large strokes.")]
    public ClampedFloatParameter strokeFlowFollow = new ClampedFloatParameter(1f, 0f, 1f);
    public ClampedFloatParameter pigmentContrast = new ClampedFloatParameter(0.6f, 0f, 2f);
    public ClampedFloatParameter strokeEdgeDarkening = new ClampedFloatParameter(0.35f, 0f, 1f);

    [Header("Colour variation per stroke")]
    [Tooltip("Max hue shift per stroke in degrees (+/-).")]
    public ClampedFloatParameter hueVariation = new ClampedFloatParameter(10f, 0f, 45f);
    public ClampedFloatParameter saturationVariation = new ClampedFloatParameter(0.1f, 0f, 0.5f);
    public ClampedFloatParameter valueVariation = new ClampedFloatParameter(0.08f, 0f, 0.5f);

    [Header("Colour bleeding (original wet-on-dry bleed)")]
    [Tooltip("Old 'Color Bleed'. Scales how far the 7-tap smear reaches. 0 = off (and the depth texture is not requested).")]
    public ClampedFloatParameter bleed = new ClampedFloatParameter(1f, 0f, 1f);
    [Tooltip("Distance of the first tap in pixels (at Reference Height). Taps sit at 1x, 2x and 3x this. The old shader used 1.5.")]
    public ClampedFloatParameter bleedStep = new ClampedFloatParameter(1.5f, 0f, 8f);
    [Tooltip("Direction of the smear on surfaces, in degrees. The old shader's 3.62 rad = 207.4 deg.")]
    public ClampedFloatParameter bleedAngle = new ClampedFloatParameter(207.4f, 0f, 360f);

    [Header("Painterly cast shadows (real-time lights)")]
    [Tooltip("0 = off. Repaints the shadows cast by objects (real-time shadows of the main light and additional lights) so their edges follow the brush strokes.")]
    public ClampedFloatParameter shadowPaint = new ClampedFloatParameter(0.8f, 0f, 1f);
    [Tooltip("How many additional (spot / point) lights get their shadows repainted, in addition to the main light. Each one costs two more shadow lookups per pixel. Quest mode caps this at 1.")]
    public ClampedIntParameter shadowAdditionalLights = new ClampedIntParameter(2, 0, 3);
    [Tooltip("How far (pixels at Reference Height) a brush stroke can push the shadow boundary. Bigger = more ragged, brushy edges.")]
    public ClampedFloatParameter shadowWobble = new ClampedFloatParameter(14f, 0f, 64f);
    [Tooltip("Crispness of the repainted edge. Small = hard painted shapes, large = soft wash.")]
    public ClampedFloatParameter shadowSoftness = new ClampedFloatParameter(0.12f, 0.02f, 0.5f);
    [Tooltip("Roughly what fraction of the light is still there inside a shadow (ambient / total). Lower it for very dark shadows. Only affects how the boundary is repainted.")]
    public ClampedFloatParameter shadowAmbient = new ClampedFloatParameter(0.35f, 0.05f, 0.9f);
    [Tooltip("Extra darkening of the shadow areas.")]
    public ClampedFloatParameter shadowDarken = new ClampedFloatParameter(0.15f, 0f, 1f);
    [Tooltip("Colour multiplied into the shadows (cool by default, like painted shade).")]
    public ColorParameter shadowTint = new ColorParameter(new Color(0.82f, 0.88f, 1f, 1f), false, false, false);
    [Tooltip("Darker pigment pooling along the shadow boundary.")]
    public ClampedFloatParameter shadowEdge = new ClampedFloatParameter(0.35f, 0f, 1f);

    [Header("Edges")]
    public ClampedFloatParameter edgeDarkening = new ClampedFloatParameter(0.25f, 0f, 1f);
    public ClampedFloatParameter edgeSensitivity = new ClampedFloatParameter(4f, 0f, 20f);

    [Header("Canvas")]
    public ClampedFloatParameter canvasStrength = new ClampedFloatParameter(0.3f, 0f, 1f);
    [Tooltip("Size in pixels of one canvas texture tile (at Reference Height).")]
    public MinFloatParameter canvasSize = new MinFloatParameter(400f, 16f);
    [Tooltip("Average brightness of your canvas texture (0.72 for the supplied Canvas_Weave_1024).")]
    public ClampedFloatParameter canvasMidpoint = new ClampedFloatParameter(0.72f, 0.1f, 1f);

    [Header("Re-roll (strokes never move, they only get re-placed / re-textured)")]
    [Tooltip("How many times per second every stroke is re-rolled (new position, brush tile, colour). 0 = frozen. Multiplied by PainterlyAnimationController if present.")]
    public ClampedFloatParameter animationSpeed = new ClampedFloatParameter(4f, 0f, 30f);

    public bool IsActive() => active && intensity.value > 0f;
}
