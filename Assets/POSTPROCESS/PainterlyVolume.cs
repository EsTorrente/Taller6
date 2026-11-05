using System;
using UnityEngine;
using UnityEngine.Rendering;

public enum PainterlyResolution { Full = 1, Half = 2, Quarter = 4 }

[Serializable]
public sealed class PainterlyResolutionParameter : VolumeParameter<PainterlyResolution>
{
    public PainterlyResolutionParameter(PainterlyResolution value, bool overrideState = false) : base(value, overrideState) { }
}

/// <summary>Watercolour look. Add via Volume > Add Override > Post-processing > Painterly Kuwahara.</summary>
[Serializable]
[VolumeComponentMenu("Post-processing/Painterly Kuwahara")] // name kept so existing profiles keep their override
public sealed class PainterlyVolume : VolumeComponent
{
    [Header("Master")]
    [Tooltip("Mobile / standalone Quest mode: cheaper smear and crevice taps, flow map at Quarter res, max 1 extra light for shadows.")]
    public BoolParameter questMode = new BoolParameter(false);
    public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);
    [Tooltip("Resolution of the small flow map (contour direction + colour edges). Quarter is plenty.")]
    public PainterlyResolutionParameter resolution = new PainterlyResolutionParameter(PainterlyResolution.Quarter);
    [Tooltip("Interpret pixel sizes relative to Reference Height so the look is identical at any resolution.")]
    public BoolParameter scaleWithResolution = new BoolParameter(true);
    public MinFloatParameter referenceHeight = new MinFloatParameter(1080f, 144f);
    [Tooltip("true: noise/paper are anchored to the view direction (no 'dirty lens' feel in VR). false: locked to the screen.")]
    public BoolParameter anchorToView = new BoolParameter(true);
    [Tooltip("Speed of the paper-wetness flow. Fully continuous, never snaps. Multiplied by PainterlyAnimationController if present. 0 = frozen.")]
    public ClampedFloatParameter animationSpeed = new ClampedFloatParameter(0.3f, 0f, 5f);

    [Header("Wet paper: noise distortion + pigment flow")]
    [Tooltip("Size (px at Reference Height) of the low-frequency noise that wobbles the image.")]
    public MinFloatParameter noiseScale = new MinFloatParameter(180f, 16f);
    [Tooltip("How far (px) the noise pushes the image around everywhere.")]
    public ClampedFloatParameter wobble = new ClampedFloatParameter(3f, 0f, 24f);
    [Tooltip("Smears colour along the contours of the image (flat areas melt into washes, edges stay).")]
    public ClampedFloatParameter flowSmear = new ClampedFloatParameter(0.8f, 0f, 1f);
    [Tooltip("Reach of one smear tap in px. Taps sit at 1x, 2x, 3x.")]
    public ClampedFloatParameter flowLength = new ClampedFloatParameter(3f, 0.5f, 12f);
    [Tooltip("Uneven pigment density across the paper.")]
    public ClampedFloatParameter fillNoise = new ClampedFloatParameter(0.15f, 0f, 0.6f);
    [Tooltip("Size (px) of the pigment unevenness.")]
    public MinFloatParameter pigmentScale = new MinFloatParameter(260f, 16f);

    [Header("Layered washes: soft tone steps")]
    public ClampedFloatParameter stepAmount = new ClampedFloatParameter(0.6f, 0f, 1f);
    [Tooltip("Number of tone levels. 2-4 = chunky stacked washes.")]
    public ClampedIntParameter steps = new ClampedIntParameter(4, 2, 8);
    [Tooltip("Soft-edged (1) vs hard cel-like (0.02) transition between tone levels.")]
    public ClampedFloatParameter stepSoftness = new ClampedFloatParameter(0.35f, 0.02f, 1f);
    [Tooltip("How much the noise roughens the borders between tone levels (irregular, blooming borders).")]
    public ClampedFloatParameter stepNoise = new ClampedFloatParameter(0.06f, 0f, 0.3f);

    [Header("Pigment pooling (edges + crevices)")]
    [Tooltip("Dark, saturated pigment along depth and normal discontinuities.")]
    public ClampedFloatParameter poolStrength = new ClampedFloatParameter(0.6f, 0f, 1f);
    [Tooltip("Width of the pooled edge in px.")]
    public ClampedFloatParameter poolWidth = new ClampedFloatParameter(2f, 0.5f, 10f);
    public ClampedFloatParameter depthEdgeSensitivity = new ClampedFloatParameter(1f, 0f, 4f);
    public ClampedFloatParameter normalEdgeSensitivity = new ClampedFloatParameter(1f, 0f, 4f);
    [Tooltip("Edges that come from the image colours themselves (textures, painted details).")]
    public ClampedFloatParameter colorEdge = new ClampedFloatParameter(0.25f, 0f, 1f);
    public ClampedFloatParameter colorEdgeSensitivity = new ClampedFloatParameter(4f, 0f, 20f);
    [Tooltip("Darkening in concave corners and crevices (cheap depth-based occlusion).")]
    public ClampedFloatParameter creviceStrength = new ClampedFloatParameter(0.6f, 0f, 1f);
    [Tooltip("Crevice search radius in px.")]
    public ClampedFloatParameter creviceRadius = new ClampedFloatParameter(10f, 2f, 40f);
    [Tooltip("0 = plain darkening, 1+ = darker and more saturated, like real pooled paint.")]
    public ClampedFloatParameter pigmentSaturation = new ClampedFloatParameter(0.6f, 0f, 1.5f);

    [Header("Blooming silhouettes")]
    [Tooltip("How far (px) the noise can push colour past object silhouettes.")]
    public ClampedFloatParameter silhouetteBleed = new ClampedFloatParameter(8f, 0f, 40f);
    [Tooltip("How much colour from across the boundary leaks in (soft edge).")]
    public ClampedFloatParameter bleedFeather = new ClampedFloatParameter(0.6f, 0f, 1f);

    [Header("Painted cast shadows (real-time lights)")]
    public ClampedFloatParameter shadowPaint = new ClampedFloatParameter(0.8f, 0f, 1f);
    [Tooltip("Extra spot/point lights whose shadows are repainted (Quest caps this at 1).")]
    public ClampedIntParameter shadowAdditionalLights = new ClampedIntParameter(2, 0, 3);
    [Tooltip("How far (px) the noise pushes the shadow boundary.")]
    public ClampedFloatParameter shadowWobble = new ClampedFloatParameter(14f, 0f, 64f);
    public ClampedFloatParameter shadowSoftness = new ClampedFloatParameter(0.18f, 0.02f, 0.5f);
    public ClampedFloatParameter shadowAmbient = new ClampedFloatParameter(0.35f, 0.05f, 0.9f);
    public ClampedFloatParameter shadowDarken = new ClampedFloatParameter(0.15f, 0f, 1f);
    public ColorParameter shadowTint = new ColorParameter(new Color(0.82f, 0.88f, 1f, 1f), false, false, false);
    public ClampedFloatParameter shadowEdge = new ClampedFloatParameter(0.35f, 0f, 1f);

    [Header("Optional hand-drawn outline")]
    public ClampedFloatParameter outline = new ClampedFloatParameter(0f, 0f, 1f);
    public ColorParameter outlineColor = new ColorParameter(new Color(0.12f, 0.14f, 0.25f, 1f), false, false, false);

    [Header("Paper")]
    public ClampedFloatParameter canvasStrength = new ClampedFloatParameter(0.3f, 0f, 1f);
    public MinFloatParameter canvasSize = new MinFloatParameter(400f, 16f);
    [Tooltip("Average brightness of the canvas texture (0.72 for Canvas_Weave_1024).")]
    public ClampedFloatParameter canvasMidpoint = new ClampedFloatParameter(0.72f, 0.1f, 1f);

    public bool IsActive() => active && intensity.value > 0f;
}
