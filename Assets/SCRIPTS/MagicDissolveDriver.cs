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
        [Tooltip("Appear with the dissolve over this many frames, starting at Appear Start Frame (0 = off)")]
        public float appearFrames;
        public float appearStartFrame = 1f;
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
    [Tooltip("More figure groups, each dissolving in the space of its own object (one driver for the whole scene)")]
    public Figures[] groups;

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
        CacheRandoms(figures);
        if (groups != null) foreach (var g in groups) CacheRandoms(g);
    }

    void CacheRandoms(Figures f)
    {
        if (f == null || f.renderers == null) return;
        foreach (var r in f.renderers)
            if (r && !figureRandoms.ContainsKey(r))
                figureRandoms[r] = Random01(r.name);
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
                if (kid.appearFrames > 0f && frame < kid.appearStartFrame + kid.appearFrames)
                {
                    // sweep the cut through the kid's own gradient range: fully cut -> fully shown, like the figures
                    float t = Mathf.Clamp01((frame - kid.appearStartFrame) / kid.appearFrames);
                    if (GradientRange(kid, out float gMin, out float gMax))
                        x = Mathf.Lerp(0.65f - gMin, 0.35f - gMax, t);
                }
                foreach (var r in kid.renderers) Set(r, kid.space, new Vector4(x, 0f, 0f, 0f), 0f);
            }
        }

        ApplyFigures(figures);
        if (groups != null) foreach (var g in groups) ApplyFigures(g);
    }

    // Range of the shader's gradient coordinate (Mapping(object coords).x, before the offset) over the kid's bounds
    static bool GradientRange(Kid kid, out float gMin, out float gMax)
    {
        gMin = float.PositiveInfinity; gMax = float.NegativeInfinity;
        var w2o = kid.space.worldToLocalMatrix;
        foreach (var r in kid.renderers)
        {
            if (!r || !r.sharedMaterial) continue;
            var m = r.sharedMaterial;
            Vector3 loc = m.GetVector("_MagicMapLocation"), rot = m.GetVector("_MagicMapRotation"), scl = m.GetVector("_MagicMapScale");
            Bounds b = r.bounds;
            for (int i = 0; i < 8; i++)
            {
                var c = new Vector3((i & 1) == 0 ? b.min.x : b.max.x, (i & 2) == 0 ? b.min.y : b.max.y, (i & 4) == 0 ? b.min.z : b.max.z);
                var o = w2o.MultiplyPoint3x4(c); o.x = -o.x;
                float g = Mapping(o, loc, rot, scl).x;
                gMin = Mathf.Min(gMin, g); gMax = Mathf.Max(gMax, g);
            }
        }
        return gMin <= gMax;
    }

    // Blender Mapping node (Point), same as MagicMapping in MagicDissolve.hlsl
    static Vector3 Mapping(Vector3 v, Vector3 loc, Vector3 r, Vector3 s)
    {
        float ci = Mathf.Cos(r.x), cj = Mathf.Cos(r.y), ch = Mathf.Cos(r.z), si = Mathf.Sin(r.x), sj = Mathf.Sin(r.y), sh = Mathf.Sin(r.z);
        float cc = ci * ch, cs = ci * sh, sc = si * ch, ss = si * sh;
        v = Vector3.Scale(v, s);
        return new Vector3(cj * ch * v.x + (sj * sc - cs) * v.y + (sj * cc + ss) * v.z,
                           cj * sh * v.x + (sj * ss + cc) * v.y + (sj * cs - sc) * v.z,
                           -sj * v.x + cj * si * v.y + cj * ci * v.z) + loc;
    }

    void ApplyFigures(Figures f)
    {
        if (f == null || !f.space || f.renderers == null) return;
        float height = BlenderPosition(f.space).z;
        float phase = Mathf.Lerp(1f, -1f, Mathf.InverseLerp(f.heightRange.x, f.heightRange.y, height));
        foreach (var r in f.renderers)
        {
            if (r)
            {
                float randVal = figureRandoms.TryGetValue(r, out var val) ? val : 0.5f;
                Set(r, f.space, Vector4.zero, randVal * f.maxOffset * phase);
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

    // Blender's Object Info > Random for a non-instanced object: hash_uint2(hash_string(name), 0) / 0xFFFFFFFF
    // (Cycles util/hash.h, same as EEVEE). Must match Blender exactly: it offsets when each object appears.
    static float Random01(string s)
    {
        uint i = 0;
        foreach (byte ch in System.Text.Encoding.UTF8.GetBytes(s)) i = i * 37u + ch;
        uint a, b, c;
        a = b = c = 0xdeadbeefu + (2u << 2) + 13u;
        a += i;
        c ^= b; c -= Rot(b, 14);
        a ^= c; a -= Rot(c, 11);
        b ^= a; b -= Rot(a, 25);
        c ^= b; c -= Rot(b, 16);
        a ^= c; a -= Rot(c, 4);
        b ^= a; b -= Rot(a, 14);
        c ^= b; c -= Rot(b, 24);
        return (float)(c / (double)0xFFFFFFFFu);
    }

    static uint Rot(uint x, int k) => (x << k) | (x >> (32 - k));
}