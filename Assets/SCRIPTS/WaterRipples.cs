using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// Ripple rings on the NearWater surface around anything that goes through it.
// A small top-down camera renders only the thin layer at the waterline. Wherever something shows up there,
// rings are emitted that grow to Contact Ripple Size over Contact Ripple Life and fade out; when it leaves the
// water no new rings start. agua_cercana draws the rings.
// Ring settings live on the water material: Contact Ripple Depth / Rate / Size / Life / Width / Amount / Color.
[RequireComponent(typeof(Renderer))]
public class WaterRipples : MonoBehaviour
{
    const int MaxRipples = 32; // same as WATER_MAX_RIPPLES in agua_cercana.hlsl

    [Tooltip("Size of the square area checked for things in the water, centred under the viewer (m)")]
    public float areaSize = 16f;
    public int resolution = 256;
    [Tooltip("Camera the area follows; empty = the camera that renders to the headset / screen")]
    public Camera viewer;
    [Tooltip("Check the waterline every this many frames (2 = every other frame)")]
    public int maskInterval = 2;

    struct Ripple
    {
        public Vector2 position;
        public float born;
        public float seed;
    }

    static readonly int RipplesId = Shader.PropertyToID("_WaterRipples");
    static readonly int CountId = Shader.PropertyToID("_WaterRippleCount");
    static readonly int SizeId = Shader.PropertyToID("_WaterRippleSize");
    static readonly int WidthId = Shader.PropertyToID("_WaterRippleWidth");

    Renderer water;
    Camera maskCamera;
    RenderTexture mask;
    bool waiting;
    readonly List<Ripple> ripples = new List<Ripple>();
    readonly Dictionary<Vector2Int, Vector3> contacts = new Dictionary<Vector2Int, Vector3>(); // x, z sums and texel count
    readonly Dictionary<Vector2Int, float> lastEmitted = new Dictionary<Vector2Int, float>();
    readonly List<Vector2Int> stale = new List<Vector2Int>();
    readonly Vector4[] packed = new Vector4[MaxRipples];
    Vector2 center;
    bool maskRendered;

    void OnEnable()
    {
        water = GetComponent<Renderer>();
        // the water lives on the Water layer so it never ends up in its own mask
        water.gameObject.layer = LayerMask.NameToLayer("Water");

        mask = new RenderTexture(resolution, resolution, 16, RenderTextureFormat.ARGB32) { name = "WaterRippleMask" };
        var go = new GameObject("WaterRippleMaskCamera") { hideFlags = HideFlags.HideAndDontSave };
        maskCamera = go.AddComponent<Camera>();
        maskCamera.clearFlags = CameraClearFlags.SolidColor;
        maskCamera.backgroundColor = Color.clear;
        maskCamera.cullingMask = ~(1 << water.gameObject.layer);
        maskCamera.targetTexture = mask;
        maskCamera.stereoTargetEye = StereoTargetEyeMask.None;
        maskCamera.allowMSAA = false;
        maskCamera.allowHDR = false;
        maskCamera.depth = -100;
        maskCamera.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
        var data = maskCamera.GetUniversalAdditionalCameraData();
        data.renderShadows = false;
        data.renderPostProcessing = false;
        data.requiresDepthTexture = false;
        data.requiresColorTexture = false;
        data.antialiasing = AntialiasingMode.None;
    }

    void OnDisable()
    {
        if (maskCamera) Destroy(maskCamera.gameObject);
        mask.Release();
        ripples.Clear();
        contacts.Clear();
        Shader.SetGlobalFloat(CountId, 0f);
    }

    void LateUpdate()
    {
        if (!viewer || !viewer.isActiveAndEnabled) viewer = FindViewer();
        Material settings = water.sharedMaterial;
        float depth = settings.GetFloat("_ContactDepth");
        float rate = settings.GetFloat("_ContactRate");
        float size = settings.GetFloat("_ContactSize");
        float life = Mathf.Max(settings.GetFloat("_ContactLife"), 0.01f);
        float now = Time.time;
        Vector3 at = viewer ? viewer.transform.position : transform.position;

        // emit from every spot that was in the water in the last mask, at most Rate rings per second each
        foreach (var contact in contacts)
        {
            if (lastEmitted.TryGetValue(contact.Key, out float last) && now - last < 1f / Mathf.Max(rate, 0.01f)) continue;
            lastEmitted[contact.Key] = now;
            Emit(new Vector2(contact.Value.x, contact.Value.y) / contact.Value.z, at);
        }
        stale.Clear();
        foreach (var spot in lastEmitted) if (now - spot.Value > 2f) stale.Add(spot.Key);
        foreach (var key in stale) lastEmitted.Remove(key);

        // rings grow to Size over Life, then they're gone
        ripples.RemoveAll(r => now - r.born >= life);
        for (int i = 0; i < ripples.Count; i++)
            packed[i] = new Vector4(ripples[i].position.x, ripples[i].position.y, (now - ripples[i].born) / life, ripples[i].seed);
        Shader.SetGlobalVectorArray(RipplesId, packed);
        Shader.SetGlobalFloat(CountId, ripples.Count);
        Shader.SetGlobalFloat(SizeId, size);
        Shader.SetGlobalFloat(WidthId, settings.GetFloat("_ContactWidth"));

        // read back the mask the camera rendered last frame
        float cell = Mathf.Max(0.1f, size * 0.5f);
        if (maskRendered && !waiting && SystemInfo.supportsAsyncGPUReadback)
        {
            waiting = true;
            Vector2 maskCenter = center;
            AsyncGPUReadback.Request(mask, 0, TextureFormat.Alpha8, request => ReadMask(request, maskCenter, cell));
        }

        // next mask, every Mask Interval frames: look down at the slab from the top of the waves to Contact Ripple
        // Depth under the lowest point. The projection is mirrored, which flips the culling, so the camera sees the
        // inside of whatever the slab cuts.
        maskRendered = !waiting && Time.frameCount % Mathf.Max(1, maskInterval) == 0;
        maskCamera.enabled = maskRendered;
        if (!maskRendered) return;
        float texel = areaSize / resolution;
        center = new Vector2(Mathf.Round(at.x / texel) * texel, Mathf.Round(at.z / texel) * texel);
        Bounds bounds = water.bounds;
        float slab = bounds.size.y + depth;
        float half = areaSize * 0.5f;
        maskCamera.transform.position = new Vector3(center.x, bounds.max.y, center.y);
        maskCamera.orthographic = true;
        maskCamera.orthographicSize = half;
        maskCamera.nearClipPlane = 0f;
        maskCamera.farClipPlane = slab;
        maskCamera.projectionMatrix = Matrix4x4.Scale(new Vector3(1f, -1f, 1f)) * Matrix4x4.Ortho(-half, half, -half, half, 0f, slab);
    }

    // group the texels that have something in the water into spots of half a ring's size
    void ReadMask(AsyncGPUReadbackRequest request, Vector2 maskCenter, float cell)
    {
        waiting = false;
        if (request.hasError || !this) return;
        var pixels = request.GetData<byte>();
        contacts.Clear();
        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                if (pixels[y * resolution + x] < 128) continue;
                // the mask is mirrored top to bottom, so texture rows run towards -Z
                float wx = maskCenter.x + ((x + 0.5f) / resolution - 0.5f) * areaSize;
                float wz = maskCenter.y - ((y + 0.5f) / resolution - 0.5f) * areaSize;
                var key = new Vector2Int(Mathf.FloorToInt(wx / cell), Mathf.FloorToInt(wz / cell));
                contacts.TryGetValue(key, out Vector3 sum);
                contacts[key] = sum + new Vector3(wx, wz, 1f);
            }
        }
    }

    // when all rings are taken, a new one replaces the one furthest from the viewer if it is closer
    void Emit(Vector2 position, Vector3 viewerPosition)
    {
        // the seed gives every ring its own wobble, thickness and gaps
        var ripple = new Ripple { position = position, born = Time.time, seed = Random.Range(0f, 100f) };
        if (ripples.Count < MaxRipples)
        {
            ripples.Add(ripple);
            return;
        }
        Vector2 eye = new Vector2(viewerPosition.x, viewerPosition.z);
        int furthest = 0;
        for (int i = 1; i < ripples.Count; i++)
            if ((ripples[i].position - eye).sqrMagnitude > (ripples[furthest].position - eye).sqrMagnitude) furthest = i;
        if ((position - eye).sqrMagnitude < (ripples[furthest].position - eye).sqrMagnitude) ripples[furthest] = ripple;
    }

    Camera FindViewer()
    {
        if (Camera.main) return Camera.main;
        foreach (var cam in Camera.allCameras)
            if (cam != maskCamera && !cam.targetTexture) return cam;
        return null;
    }
}
