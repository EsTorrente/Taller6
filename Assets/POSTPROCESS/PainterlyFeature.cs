using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

/// <summary>
/// Brush-stroke atlas + canvas + surface-aligned colour bleed (Unity 6 / URP, RenderGraph, XR safe).
/// Two passes: a tiny flow-tensor pass and one full-res composite. All tweakables live in the PainterlyVolume.
/// </summary>
public class PainterlyFeature : ScriptableRendererFeature
{
    [Header("Assets")]
    public Shader shader;
    [Tooltip("Brush stamp atlas (white strokes on black). Import with sRGB OFF, mipmaps ON, Wrap = Clamp.")]
    public Texture2D brushTexture;
    public int atlasColumns = 6;
    public int atlasRows = 6;
    [Tooltip("Tileable canvas texture. Import with sRGB OFF, mipmaps ON, Wrap = Repeat.")]
    public Texture2D canvasTexture;

    [Header("Injection")]
    public RenderPassEvent injectionPoint = RenderPassEvent.BeforeRenderingPostProcessing;
    public bool applyInSceneView = false;

    // ---- Runtime animation control (see PainterlyAnimationController) -------------------------------------
    public static float AnimationSpeedMultiplier = 1f;
    public static bool UseUnscaledTime = true;

    static float s_Phase;
    static int s_LastPhaseFrame = -1;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
    static void ResetStatics()
    {
        AnimationSpeedMultiplier = 1f;
        UseUnscaledTime = true;
        s_Phase = 0f;
        s_LastPhaseFrame = -1;
    }

    /// <summary>Advance the stroke re-roll by exactly one step (handy for stop-motion style control).</summary>
    public static void StepAnimation() { s_Phase = Mathf.Floor(s_Phase) + 1f; }

    Material material;
    PainterlyPass pass;

    public override void Create()
    {
        if (shader == null) { pass = null; return; }
        CoreUtils.Destroy(material);
        material = CoreUtils.CreateEngineMaterial(shader);
        pass = new PainterlyPass(material);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (pass == null || material == null) return;

        var camType = renderingData.cameraData.cameraType;
        if (camType != CameraType.Game && !(applyInSceneView && camType == CameraType.SceneView)) return;

        var v = VolumeManager.instance.stack.GetComponent<PainterlyVolume>();
        if (v == null || !v.IsActive()) return;

        // Accumulated phase (not Time * speed) so changing the speed never makes the strokes jump.
        if (s_LastPhaseFrame != Time.frameCount)
        {
            s_LastPhaseFrame = Time.frameCount;
            float dt = UseUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;
            s_Phase += dt * v.animationSpeed.value * AnimationSpeedMultiplier;
        }

        pass.renderPassEvent = injectionPoint;
        pass.Setup(v, brushTexture, atlasColumns, atlasRows, canvasTexture, Mathf.Floor(s_Phase) % 100000f);
        renderer.EnqueuePass(pass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(material);
        material = null;
    }

    // =========================================================================================================
    sealed class PainterlyPass : ScriptableRenderPass
    {
        const int PassTensor = 0, PassComposite = 1;

        static readonly int idSrc = Shader.PropertyToID("_PaintSrc");
        static readonly int idTensor = Shader.PropertyToID("_PaintTensor");
        static readonly int idAtlas = Shader.PropertyToID("_PaintBrushAtlas");
        static readonly int idCanvas = Shader.PropertyToID("_PaintCanvas");
        static readonly int idTexel = Shader.PropertyToID("_PaintTexel");
        static readonly int idFullTexel = Shader.PropertyToID("_PaintFullTexel");
        static readonly int idDown = Shader.PropertyToID("_DownFactor");
        static readonly int idIntensity = Shader.PropertyToID("_Intensity");
        static readonly int idStrokeStrength = Shader.PropertyToID("_StrokeStrength");
        static readonly int idStrokeCell = Shader.PropertyToID("_StrokeCellPx");
        static readonly int idStrokeStamp = Shader.PropertyToID("_StrokeStamp");
        static readonly int idStrokeElong = Shader.PropertyToID("_StrokeElong");
        static readonly int idFlow = Shader.PropertyToID("_FlowFollow");
        static readonly int idPigment = Shader.PropertyToID("_PigmentContrast");
        static readonly int idStrokeEdge = Shader.PropertyToID("_StrokeEdgeDark");
        static readonly int idHue = Shader.PropertyToID("_HueVar");
        static readonly int idSat = Shader.PropertyToID("_SatVar");
        static readonly int idVal = Shader.PropertyToID("_ValVar");
        static readonly int idSeed = Shader.PropertyToID("_AnimSeed");
        static readonly int idAtlasGrid = Shader.PropertyToID("_AtlasGrid");
        static readonly int idAtlasLod = Shader.PropertyToID("_AtlasLod");
        static readonly int idBleed = Shader.PropertyToID("_Bleed");
        static readonly int idBleedPx = Shader.PropertyToID("_BleedPx");
        static readonly int idBleedRot = Shader.PropertyToID("_BleedRot");
        static readonly int idEdgeDark = Shader.PropertyToID("_EdgeDark");
        static readonly int idEdgeGain = Shader.PropertyToID("_EdgeGain");
        static readonly int idCanvasStrength = Shader.PropertyToID("_CanvasStrength");
        static readonly int idCanvasPx = Shader.PropertyToID("_CanvasPx");
        static readonly int idCanvasMid = Shader.PropertyToID("_CanvasMid");
        static readonly int idLite = Shader.PropertyToID("_Lite");
        static readonly int idShadowAddCount = Shader.PropertyToID("_ShadowAddCount");
        static readonly int idShadowPaint = Shader.PropertyToID("_ShadowPaint");
        static readonly int idShadowWobble = Shader.PropertyToID("_ShadowWobblePx");
        static readonly int idShadowSoft = Shader.PropertyToID("_ShadowSoft");
        static readonly int idShadowAmbient = Shader.PropertyToID("_ShadowAmbient");
        static readonly int idShadowDarken = Shader.PropertyToID("_ShadowDarken");
        static readonly int idShadowEdge = Shader.PropertyToID("_ShadowEdge");
        static readonly int idShadowTint = Shader.PropertyToID("_ShadowTint");

        // Per-frame parameter block. Allocated once; mutated each frame.
        sealed class Params
        {
            public float down, intensity;
            public float strokeStrength, strokeCell, strokeStamp, strokeElong, flow, pigment, strokeEdge;
            public float hue, sat, val, seed, atlasCols, atlasRows, atlasLod;
            public float bleed, bleedPx, bleedCos, bleedSin;
            public float edgeDark, edgeGain, canvasStrength, canvasPx, canvasMid;
            public float lite, shadowAddCount, shadowPaint, shadowWobble, shadowSoft, shadowAmbient, shadowDarken, shadowEdge;
            public Vector4 shadowTint;
            public Texture atlas, canvas;
        }

        sealed class PassData
        {
            public Material mat;
            public int pass;
            public TextureHandle src, tensor;
            public Vector4 texel, fullTexel;
            public Params p;
        }

        readonly Material mat;
        readonly Params p = new Params();
        static readonly MaterialPropertyBlock s_Mpb = new MaterialPropertyBlock();
        static readonly BaseRenderFunc<PassData, RasterGraphContext> s_Exec = Exec; // cached: no per-frame delegate alloc

        PainterlyVolume vol;

        public PainterlyPass(Material m)
        {
            mat = m;
            ConfigureInput(ScriptableRenderPassInput.None);
            requiresIntermediateTexture = true;
        }

        public void Setup(PainterlyVolume v, Texture2D atlas, int cols, int rows, Texture2D canvas, float seed)
        {
            vol = v;
            p.atlas = atlas != null ? atlas : Texture2D.blackTexture;   // no atlas -> no strokes
            p.canvas = canvas != null ? canvas : Texture2D.whiteTexture;
            p.atlasCols = Mathf.Max(1, cols);
            p.atlasRows = Mathf.Max(1, rows);
            p.seed = seed;

            // Depth is only needed by the bleed. No bleed -> no depth prepass / copy.
            bool needDepth = (v.bleed.value > 0f && v.bleedStep.value > 0f) || v.shadowPaint.value > 0f;
            ConfigureInput(needDepth ? ScriptableRenderPassInput.Depth : ScriptableRenderPassInput.None);
        }

        // -----------------------------------------------------------------------------------------------------
        public override void RecordRenderGraph(RenderGraph rg, ContextContainer frameData)
        {
            var res = frameData.Get<UniversalResourceData>();
            if (res.isActiveTargetBackBuffer || vol == null) return;

            var cam = frameData.Get<UniversalCameraData>();
            var desc = cam.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.useMipMap = false;
            desc.autoGenerateMips = false;

            int fullW = desc.width, fullH = desc.height;
            int factor = vol.questMode.value ? 4 : (int)vol.resolution.value;
            int workW = Mathf.Max(1, fullW / factor), workH = Mathf.Max(1, fullH / factor);

            var lightData = frameData.Get<UniversalLightData>();
            BuildParams(fullH, factor, Mathf.Max(0, lightData.additionalLightsCount));
            bool needDepth = (p.bleed > 0f && p.bleedPx > 0f) || p.shadowPaint > 0f;

            TextureHandle src = res.activeColorTexture;

            // 1 - flow tensor, straight from the camera colour, at working resolution
            var td = desc; td.width = workW; td.height = workH;
            td.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;   // signed values, no colour-space conversion
            td.depthStencilFormat = GraphicsFormat.None;
            var tensor = UniversalRenderer.CreateRenderGraphTexture(rg, td, "_PaintTensor", false, FilterMode.Bilinear);
            AddPass(rg, "Painterly Flow", PassTensor, src, default, tensor, workW, workH, fullW, fullH, default, default, default);

            // 2 - composite at full resolution
            var final = UniversalRenderer.CreateRenderGraphTexture(rg, desc, "_PaintFinal", false, FilterMode.Bilinear);
            TextureHandle depth = (needDepth && res.cameraDepthTexture.IsValid()) ? res.cameraDepthTexture : default;
            // The shadow map is only requested when shadows are repainted, so it is never kept alive for nothing.
            TextureHandle shadows = (p.shadowPaint > 0f && res.mainShadowsTexture.IsValid()) ? res.mainShadowsTexture : default;
            TextureHandle addShadows = (p.shadowPaint > 0f && p.shadowAddCount > 0f && res.additionalShadowsTexture.IsValid()) ? res.additionalShadowsTexture : default;
            AddPass(rg, "Painterly Composite", PassComposite, src, tensor, final, fullW, fullH, fullW, fullH, depth, shadows, addShadows);

            res.cameraColor = final;
        }

        void BuildParams(int fullH, int factor, int addLightsInScene)
        {
            var v = vol;
            float refScale = v.scaleWithResolution.value ? fullH / v.referenceHeight.value : 1f;

            p.down = factor;
            p.intensity = v.intensity.value;

            p.strokeStrength = v.strokeStrength.value;
            p.strokeCell = Mathf.Max(4f, v.strokeSize.value * refScale);
            p.strokeStamp = v.strokeStamp.value;
            p.strokeElong = v.strokeElongation.value;
            p.flow = v.strokeFlowFollow.value;
            p.pigment = v.pigmentContrast.value;
            p.strokeEdge = v.strokeEdgeDarkening.value;
            p.hue = v.hueVariation.value * Mathf.Deg2Rad;
            p.sat = v.saturationVariation.value;
            p.val = v.valueVariation.value;

            // Fixed mip level for the atlas (no derivatives across tile borders): atlas texels per screen pixel.
            float tilePx = p.atlas.width / p.atlasCols;
            float stampPx = Mathf.Max(1f, p.strokeCell * p.strokeStamp);
            float lod = Mathf.Max(0f, Mathf.Log(tilePx / stampPx, 2f) - 0.25f);
            p.atlasLod = Mathf.Min(lod, Mathf.Max(0, p.atlas.mipmapCount - 1));

            p.bleed = v.bleed.value;
            p.bleedPx = v.bleedStep.value * refScale;
            float a = v.bleedAngle.value * Mathf.Deg2Rad;
            p.bleedCos = Mathf.Cos(a);
            p.bleedSin = Mathf.Sin(a);

            p.lite = v.questMode.value ? 1f : 0f;
            p.shadowPaint = v.shadowPaint.value;
            int addWanted = v.questMode.value ? Mathf.Min(1, v.shadowAdditionalLights.value) : v.shadowAdditionalLights.value;
            p.shadowAddCount = Mathf.Min(addWanted, addLightsInScene);
            p.shadowWobble = v.shadowWobble.value * refScale;
            p.shadowSoft = v.shadowSoftness.value;
            p.shadowAmbient = Mathf.Max(0.05f, v.shadowAmbient.value);
            p.shadowDarken = v.shadowDarken.value;
            p.shadowEdge = v.shadowEdge.value;
            Color tint = v.shadowTint.value;
            if (QualitySettings.activeColorSpace == ColorSpace.Linear) tint = tint.linear;
            p.shadowTint = new Vector4(tint.r, tint.g, tint.b, 1f);

            p.edgeDark = v.edgeDarkening.value;
            p.edgeGain = v.edgeSensitivity.value;
            p.canvasStrength = v.canvasStrength.value;
            p.canvasPx = Mathf.Max(16f, v.canvasSize.value * refScale);
            p.canvasMid = v.canvasMidpoint.value;
        }

        void AddPass(RenderGraph rg, string name, int shaderPass,
                     TextureHandle src, TextureHandle tensor, TextureHandle dst,
                     int dstW, int dstH, int fullW, int fullH, TextureHandle depth, TextureHandle shadows, TextureHandle addShadows)
        {
            using (var b = rg.AddRasterRenderPass<PassData>(name, out var d))
            {
                d.mat = mat;
                d.pass = shaderPass;
                d.src = src;
                d.tensor = tensor;
                d.texel = new Vector4(1f / dstW, 1f / dstH, dstW, dstH);
                d.fullTexel = new Vector4(1f / fullW, 1f / fullH, fullW, fullH);
                d.p = p;

                b.UseTexture(src, AccessFlags.Read);
                if (tensor.IsValid()) b.UseTexture(tensor, AccessFlags.Read);
                if (depth.IsValid()) b.UseTexture(depth, AccessFlags.Read);
                if (shadows.IsValid()) b.UseTexture(shadows, AccessFlags.Read);
                if (addShadows.IsValid()) b.UseTexture(addShadows, AccessFlags.Read);
                b.SetRenderAttachment(dst, 0);
                b.SetRenderFunc(s_Exec);
            }
        }

        // Everything is bound through a MaterialPropertyBlock that is snapshotted by DrawProcedural, so values
        // can never leak between passes or cameras. The flow pass only receives what it needs.
        static void Exec(PassData d, RasterGraphContext ctx)
        {
            var b = s_Mpb;
            b.Clear();
            var p = d.p;

            b.SetTexture(idSrc, d.src);
            b.SetVector(idTexel, d.texel);
            b.SetVector(idFullTexel, d.fullTexel);

            if (d.pass == PassTensor)
            {
                b.SetFloat(idDown, p.down);
            }
            else
            {
                b.SetTexture(idTensor, d.tensor);
                b.SetTexture(idAtlas, p.atlas);
                b.SetTexture(idCanvas, p.canvas);

                b.SetFloat(idIntensity, p.intensity);
                b.SetFloat(idStrokeStrength, p.strokeStrength);
                b.SetFloat(idStrokeCell, p.strokeCell);
                b.SetFloat(idStrokeStamp, p.strokeStamp);
                b.SetFloat(idStrokeElong, p.strokeElong);
                b.SetFloat(idFlow, p.flow);
                b.SetFloat(idPigment, p.pigment);
                b.SetFloat(idStrokeEdge, p.strokeEdge);
                b.SetFloat(idHue, p.hue);
                b.SetFloat(idSat, p.sat);
                b.SetFloat(idVal, p.val);
                b.SetFloat(idSeed, p.seed);
                b.SetVector(idAtlasGrid, new Vector4(p.atlasCols, p.atlasRows, 0, 0));
                b.SetFloat(idAtlasLod, p.atlasLod);
                b.SetFloat(idBleed, p.bleed);
                b.SetFloat(idBleedPx, p.bleedPx);
                b.SetVector(idBleedRot, new Vector4(p.bleedCos, p.bleedSin, 0, 0));
                b.SetFloat(idEdgeDark, p.edgeDark);
                b.SetFloat(idEdgeGain, p.edgeGain);
                b.SetFloat(idCanvasStrength, p.canvasStrength);
                b.SetFloat(idCanvasPx, p.canvasPx);
                b.SetFloat(idCanvasMid, p.canvasMid);
                b.SetFloat(idLite, p.lite);
                b.SetFloat(idShadowAddCount, p.shadowAddCount);
                b.SetFloat(idShadowPaint, p.shadowPaint);
                b.SetFloat(idShadowWobble, p.shadowWobble);
                b.SetFloat(idShadowSoft, p.shadowSoft);
                b.SetFloat(idShadowAmbient, p.shadowAmbient);
                b.SetFloat(idShadowDarken, p.shadowDarken);
                b.SetFloat(idShadowEdge, p.shadowEdge);
                b.SetVector(idShadowTint, p.shadowTint);
            }

            ctx.cmd.DrawProcedural(Matrix4x4.identity, d.mat, d.pass, MeshTopology.Triangles, 3, 1, b);
        }
    }
}
