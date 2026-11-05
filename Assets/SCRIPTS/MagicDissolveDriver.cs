using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Playables;
using UnityEngine.Rendering;

// Drives the magic appear / disappear with cached random lookups and reduced per-frame allocations.
[ExecuteAlways]
public class MagicDissolveDriver : MonoBehaviour
{
    [Tooltip("Timeline that plays the ESCENA67 animation; its time gives the Blender frame")]
    public PlayableDirector director;
    public float framesPerSecond = 24f;
    [Tooltip("Blender frame at Timeline time 0")]
    public float firstFrame = 1f;

    [Serializable]
    public class Kid
    {
        public Transform space;
        public Transform controller;
        public Renderer[] renderers;
        public float mappingX;
        public float travel = 1.3f;
        public float fullY = 1.5664f;
        public float gateFrame = 1250f;
        public bool afterGate;
    }

    [Serializable]
    public class Figures
    {
        public Transform space;
        public Renderer[] renderers;
        public float maxOffset = 0.8f;
        public Vector2 heightRange = new Vector2(8f, 12f);
    }

    public Kid[] kids;
    public Figures figures;

    static readonly int FrameId = Shader.PropertyToID("_MagicFrame");
    static readonly int WorldToObjectId = Shader.PropertyToID("_MagicWorldToObject");
    static readonly int MapOffsetId = Shader.PropertyToID("_MagicMapOffset");
    static readonly int GradientOffsetId = Shader.PropertyToID("_MagicGradientOffset");

    MaterialPropertyBlock block;
    Dictionary<Renderer, float> figureRandoms = new Dictionary<Renderer, float>();

    void OnEnable()
    {
        RenderPipelineManager.beginContextRendering += Apply;
        CacheRandoms();
    }

    void OnDisable()
    {
        RenderPipelineManager.beginContextRendering -= Apply;
    }

    void CacheRandoms()
    {
        figureRandoms.Clear();
        if (figures != null && figures.renderers != null)
        {
            foreach (var r in figures.renderers)
            {
                if (r && !figureRandoms.ContainsKey(r))
                {
                    figureRandoms[r] = Random01(r.name);
                }
            }
        }
    }

    static Vector3 BlenderPosition(Transform t) => Vector3.Scale(t.localPosition, new Vector3(-1f, 1f, 1f));

    void Apply(ScriptableRenderContext context, System.Collections.Generic.List<Camera> cameras)
    {
        block ??= new MaterialPropertyBlock();
        float time = director ? (float)director.time : Time.time;
        float frame = firstFrame + time * framesPerSecond;
        Shader.SetGlobalFloat(FrameId, frame);

        if (kids != null)
        {
            foreach (var kid in kids)
            {
                if (!kid.space || !kid.controller) continue;
                float gate = Mathf.Clamp01(kid.afterGate ? frame - kid.gateFrame : kid.gateFrame - frame);
                float x = kid.mappingX - kid.travel * Mathf.Clamp01(BlenderPosition(kid.controller).y / kid.fullY) * gate;
                foreach (var r in kid.renderers) Set(r, kid.space, new Vector4(x, 0f, 0f, 0f), 0f);
            }
        }

        if (figures != null && figures.space)
        {
            float height = BlenderPosition(figures.space).z;
            float phase = Mathf.Lerp(1f, -1f, Mathf.InverseLerp(figures.heightRange.x, figures.heightRange.y, height));
            foreach (var r in figures.renderers)
            {
                if (r)
                {
                    float randVal = figureRandoms.TryGetValue(r, out var val) ? val : 0.5f;
                    Set(r, figures.space, Vector4.zero, randVal * figures.maxOffset * phase);
                }
            }
        }
    }

    void Set(Renderer r, Transform space, Vector4 mapOffset, float gradientOffset)
    {
        if (!r) return;
        r.GetPropertyBlock(block);
        block.SetMatrix(WorldToObjectId, space.worldToLocalMatrix);
        block.SetVector(MapOffsetId, mapOffset);
        block.SetFloat(GradientOffsetId, gradientOffset);
        r.SetPropertyBlock(block);
    }

    static float Random01(string s)
    {
        uint h = 2166136261u;
        foreach (char c in s) h = (h ^ c) * 16777619u;
        return (h & 0xFFFFFF) / 16777216f;
    }
}