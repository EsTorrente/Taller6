using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

public class PainterlyFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent injectionPoint = RenderPassEvent.BeforeRenderingPostProcessing;

        [Header("Watercolor Wash & Strokes")]
        public Texture2D brushTexture;
        [Min(0.01f)] public float strokeScale = 0.1f;
        [Range(0, 8)] public float strokeStrength = 0.15f;
        [Range(0, 6.28f)] public float strokeAngle = 3.62f;
        [Range(0, 2)] public float washIntensity = 0.295f;
        [Range(0, 64)] public float edgeDarkening = 1.0f;
        [Range(0, 5)] public float animateSpeed = 2.14f;

        [Header("Colour Bleeding")]
        [Range(0, 1)] public float colorBleed = 1.0f;

        [Header("Canvas / Paper")]
        public Texture2D canvasTexture;
        [Min(0.1f)] public float canvasScale = 11.04f;
        [Range(0, 1)] public float canvasStrength = 0.394f;

        [Header("Distance Weighting")]
        [Range(0, 1)] public float nearWeight = 0.347f;
        [Range(0, 1)] public float farWeight = 0.728f;
        public float fadeStart = 0.23f;
        public float fadeEnd = 6.4f;
    }

    public Shader shader;
    public Settings settings = new Settings();

    Material material;
    PainterlyPass pass;

    public override void Create()
    {
        if (shader == null) return;
        material = CoreUtils.CreateEngineMaterial(shader);
        pass = new PainterlyPass(material, settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (pass == null || material == null) return;
        if (renderingData.cameraData.cameraType != CameraType.Game) return;
        pass.renderPassEvent = settings.injectionPoint;
        renderer.EnqueuePass(pass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(material);
    }

    class PainterlyPass : ScriptableRenderPass
    {
        readonly Material mat;
        readonly Settings s;

        static readonly int BrushTex = Shader.PropertyToID("_BrushTex");
        static readonly int CanvasTex = Shader.PropertyToID("_CanvasTex");

        public PainterlyPass(Material m, Settings settings)
        {
            mat = m;
            s = settings;
            ConfigureInput(ScriptableRenderPassInput.Depth);
            requiresIntermediateTexture = true;
        }

        class PassData
        {
            public TextureHandle src;
            public TextureHandle dst;
            public Material material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            if (resources.isActiveTargetBackBuffer) return;

            if (s.brushTexture) mat.SetTexture(BrushTex, s.brushTexture);
            if (s.canvasTexture) mat.SetTexture(CanvasTex, s.canvasTexture);

            mat.SetFloat("_StrokeScale", s.strokeScale);
            mat.SetFloat("_StrokeStrength", s.strokeStrength);
            mat.SetFloat("_StrokeAngle", s.strokeAngle);
            mat.SetFloat("_WashIntensity", s.washIntensity);
            mat.SetFloat("_EdgeDarkening", s.edgeDarkening);
            mat.SetFloat("_AnimateSpeed", s.animateSpeed);
            mat.SetFloat("_ColorBleed", s.colorBleed);
            mat.SetFloat("_CanvasScale", s.canvasScale);
            mat.SetFloat("_CanvasStrength", s.canvasStrength);
            mat.SetFloat("_NearWeight", s.nearWeight);
            mat.SetFloat("_FarWeight", s.farWeight);
            mat.SetFloat("_FadeStart", s.fadeStart);
            mat.SetFloat("_FadeEnd", s.fadeEnd);

            var cameraData = frameData.Get<UniversalCameraData>();
            var desc = cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            TextureHandle src = resources.activeColorTexture;
            TextureHandle dst = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_PainterlyRT", false);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Live Watercolor Pass", out var passData))
            {
                passData.src = src;
                passData.dst = dst;
                passData.material = mat;

                builder.UseTexture(src, AccessFlags.Read);
                builder.SetRenderAttachment(dst, 0);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(context.cmd, data.src, new Vector4(1, 1, 0, 0), data.material, 0);
                });
            }

            resources.cameraColor = dst;
        }
    }
}