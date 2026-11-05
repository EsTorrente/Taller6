using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

/// <summary>
/// Watercolour post effect (Unity 6 / URP, RenderGraph, XR safe). Two passes: a tiny flow-tensor pass and one
/// full-res composite that uses colour + depth + normals. All tweakables live in the PainterlyVolume.
/// </summary>
public class PainterlyFeature : ScriptableRendererFeature
{
    [Header("Assets")]
    public Shader shader;
    [Tooltip("Tileable paper texture. Import with sRGB OFF, mipmaps ON, Wrap = Repeat.")]
    public Texture2D canvasTexture;

    [Header("Injection")]
    public RenderPassEvent injectionPoint = RenderPassEvent.BeforeRenderingPostProcessing;
    public bool applyInSceneView = false;

    // ---- Runtime animation control (see PainterlyAnimationController) -----------------------------------
    public static float AnimationSpeedMultiplier = 1f;
    public static bool UseUnscaledTime = true;

    static double s_Time;
    static int s_LastFrame = -1;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
    static void ResetStatics() { AnimationSpeedMultiplier = 1f; UseUnscaledTime = true; s_Time = 0; s_LastFrame = -1; }

    /// <summary>Jump the paper flow forward by one time unit.</summary>
    public static void StepAnimation() { s_Time += 1.0; }

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

        // Accumulated time (not Time * speed) so changing the speed never makes anything jump.
        if (s_LastFrame != Time.frameCount)
        {
            s_LastFrame = Time.frameCount;
            float dt = UseUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;
            s_Time += dt * v.animationSpeed.value * AnimationSpeedMultiplier;
        }

        pass.renderPassEvent = injectionPoint;
        pass.Setup(v, canvasTexture, (float)(s_Time % 1024.0));
        renderer.EnqueuePass(pass);
    }

    protected override void Dispose(bool disposing) { CoreUtils.Destroy(material); material = null; }

    // =========================================================================================================
    sealed class PainterlyPass : ScriptableRenderPass
    {
        const int PassTensor = 0, PassComposite = 1;

        static readonly int idSrc = Shader.PropertyToID("_PaintSrc");
        static readonly int idTensor = Shader.PropertyToID("_PaintTensor");
        static readonly int idCanvas = Shader.PropertyToID("_PaintCanvas");
        static readonly int idTexel = Shader.PropertyToID("_PaintTexel");
        static readonly int idFullTexel = Shader.PropertyToID("_PaintFullTexel");
        static readonly int idDown = Shader.PropertyToID("_DownFactor");
        static readonly int idShadowTint = Shader.PropertyToID("_ShadowTint");
        static readonly int idOutlineColor = Shader.PropertyToID("_OutlineColor");
        static readonly int[] idP =
        {
            Shader.PropertyToID("_P0"), Shader.PropertyToID("_P1"), Shader.PropertyToID("_P2"),
            Shader.PropertyToID("_P3"), Shader.PropertyToID("_P4"), Shader.PropertyToID("_P5"),
            Shader.PropertyToID("_P6"), Shader.PropertyToID("_P7"), Shader.PropertyToID("_P8")
        };

        sealed class Params
        {
            public float down;
            public readonly Vector4[] v = new Vector4[9];
            public Vector4 shadowTint, outlineColor;
            public Texture canvas;
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
        static readonly BaseRenderFunc<PassData, RasterGraphContext> s_Exec = Exec;

        PainterlyVolume vol;
        float time;

        public PainterlyPass(Material m)
        {
            mat = m;
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
            requiresIntermediateTexture = true;
        }

        public void Setup(PainterlyVolume v, Texture2D canvas, float t)
        {
            vol = v;
            time = t;
            p.canvas = canvas != null ? canvas : Texture2D.whiteTexture;
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal); // both are always needed
        }

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

            TextureHandle src = res.activeColorTexture;

            var td = desc; td.width = workW; td.height = workH;
            td.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            td.depthStencilFormat = GraphicsFormat.None;
            var tensor = UniversalRenderer.CreateRenderGraphTexture(rg, td, "_PaintTensor", false, FilterMode.Bilinear);
            AddPass(rg, "Painterly Flow", PassTensor, src, default, tensor, workW, workH, fullW, fullH, default, default, default, default);

            var final = UniversalRenderer.CreateRenderGraphTexture(rg, desc, "_PaintFinal", false, FilterMode.Bilinear);
            TextureHandle depth = res.cameraDepthTexture.IsValid() ? res.cameraDepthTexture : default;
            TextureHandle normals = res.cameraNormalsTexture.IsValid() ? res.cameraNormalsTexture : default;
            bool sh = vol.shadowPaint.value > 0f;
            TextureHandle shadows = (sh && res.mainShadowsTexture.IsValid()) ? res.mainShadowsTexture : default;
            TextureHandle addShadows = (sh && p.v[7].x > 0f && res.additionalShadowsTexture.IsValid()) ? res.additionalShadowsTexture : default;
            // normals are bound together with depth through the same list
            AddPass(rg, "Painterly Composite", PassComposite, src, tensor, final, fullW, fullH, fullW, fullH, depth, normals, shadows, addShadows);

            res.cameraColor = final;
        }

        void BuildParams(int fullH, int factor, int addLightsInScene)
        {
            var v = vol;
            bool lite = v.questMode.value;
            float rs = v.scaleWithResolution.value ? fullH / v.referenceHeight.value : 1f;

            p.down = factor;
            p.v[0] = new Vector4(v.intensity.value, Mathf.Max(8f, v.noiseScale.value * rs), v.wobble.value * rs, time);
            p.v[1] = new Vector4(v.flowSmear.value, v.flowLength.value * rs, v.fillNoise.value, Mathf.Max(8f, v.pigmentScale.value * rs));
            p.v[2] = new Vector4(v.stepAmount.value, v.steps.value, v.stepSoftness.value, v.stepNoise.value);
            p.v[3] = new Vector4(v.poolStrength.value, v.poolWidth.value * rs, v.depthEdgeSensitivity.value, v.normalEdgeSensitivity.value);
            p.v[4] = new Vector4(v.colorEdge.value, v.colorEdgeSensitivity.value, v.creviceStrength.value, v.creviceRadius.value * rs);
            p.v[5] = new Vector4(v.silhouetteBleed.value * rs, v.bleedFeather.value, v.outline.value, lite ? 1f : 0f);
            p.v[6] = new Vector4(v.canvasStrength.value, Mathf.Max(16f, v.canvasSize.value * rs), v.canvasMidpoint.value, v.anchorToView.value ? 1f : 0f);
            int addWanted = lite ? Mathf.Min(1, v.shadowAdditionalLights.value) : v.shadowAdditionalLights.value;
            p.v[7] = new Vector4(Mathf.Min(addWanted, addLightsInScene), v.shadowPaint.value, v.shadowWobble.value * rs, v.shadowSoftness.value);
            p.v[8] = new Vector4(Mathf.Max(0.05f, v.shadowAmbient.value), v.shadowDarken.value, v.shadowEdge.value, v.pigmentSaturation.value);

            Color tint = v.shadowTint.value, ol = v.outlineColor.value;
            if (QualitySettings.activeColorSpace == ColorSpace.Linear) { tint = tint.linear; ol = ol.linear; }
            p.shadowTint = new Vector4(tint.r, tint.g, tint.b, 1f);
            p.outlineColor = new Vector4(ol.r, ol.g, ol.b, 1f);
        }

        void AddPass(RenderGraph rg, string name, int shaderPass, TextureHandle src, TextureHandle tensor, TextureHandle dst,
                     int dstW, int dstH, int fullW, int fullH, TextureHandle a, TextureHandle b2, TextureHandle c2, TextureHandle d2 = default)
        {
            using (var b = rg.AddRasterRenderPass<PassData>(name, out var d))
            {
                d.mat = mat; d.pass = shaderPass; d.src = src; d.tensor = tensor;
                d.texel = new Vector4(1f / dstW, 1f / dstH, dstW, dstH);
                d.fullTexel = new Vector4(1f / fullW, 1f / fullH, fullW, fullH);
                d.p = p;

                b.UseTexture(src, AccessFlags.Read);
                if (tensor.IsValid()) b.UseTexture(tensor, AccessFlags.Read);
                if (a.IsValid()) b.UseTexture(a, AccessFlags.Read);
                if (b2.IsValid()) b.UseTexture(b2, AccessFlags.Read);
                if (c2.IsValid()) b.UseTexture(c2, AccessFlags.Read);
                if (d2.IsValid()) b.UseTexture(d2, AccessFlags.Read);
                b.SetRenderAttachment(dst, 0);
                b.SetRenderFunc(s_Exec);
            }
        }

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
                b.SetTexture(idCanvas, p.canvas);
                for (int i = 0; i < idP.Length; i++) b.SetVector(idP[i], p.v[i]);
                b.SetVector(idShadowTint, p.shadowTint);
                b.SetVector(idOutlineColor, p.outlineColor);
            }
            ctx.cmd.DrawProcedural(Matrix4x4.identity, d.mat, d.pass, MeshTopology.Triangles, 3, 1, b);
        }
    }
}
