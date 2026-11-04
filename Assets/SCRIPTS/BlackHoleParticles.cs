using UnityEngine;

// Glowing particles spinning around the black hole in the plane of its disc. The Particle System is made under
// the black hole bone when the scene starts, so it grows, moves and tilts with the disc.
// Distances are in disc radii: 1 = edge of the disc, about 0.36 = the sphere.
// Particles only appear while the black hole itself is switched on and on screen.
public class BlackHoleParticles : MonoBehaviour
{
    [Tooltip("The black hole bone (Armature > Bone)")]
    public Transform bone;
    [Tooltip("The black hole sphere (BH_02); particles only appear while it is on screen")]
    public Renderer blackHole;
    public Material material;
    public float rate = 120f;
    [Tooltip("Spin speed (radians per second)")]
    public float spin = 0.5f;
    [Tooltip("Particles appear between this and the edge of the disc")]
    [Range(0f, 1f)] public float innerRadius = 0.4f;
    [Tooltip("Particle size, in disc radii")]
    public float size = 0.008f;
    public float lifetime = 4f;
    public Color color = new Color(1f, 0.6f, 0.25f);

    ParticleSystem swirl;

    void Update()
    {
        if (!swirl || !blackHole) return;
        bool shown = blackHole.enabled && blackHole.gameObject.activeInHierarchy && blackHole.isVisible;
        var emission = swirl.emission;
        if (emission.enabled != shown) emission.enabled = shown;
    }

    void Start()
    {
        if (!bone) return;
        var go = new GameObject("BlackHoleParticles");
        go.transform.SetParent(bone, false);

        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

        var main = ps.main;
        main.loop = true;
        main.startLifetime = new ParticleSystem.MinMaxCurve(lifetime * 0.6f, lifetime);
        main.startSpeed = 0f;
        main.startSize = new ParticleSystem.MinMaxCurve(size * 0.4f, size);
        main.startColor = new ParticleSystem.MinMaxGradient(color, Color.Lerp(color, Color.white, 0.6f));
        main.simulationSpace = ParticleSystemSimulationSpace.Local;
        main.scalingMode = ParticleSystemScalingMode.Hierarchy;
        main.maxParticles = Mathf.CeilToInt(rate * lifetime) + 10;
        main.cullingMode = ParticleSystemCullingMode.Pause;

        var emission = ps.emission;
        emission.rateOverTime = rate;

        // a ring in the disc plane (the bone's XZ)
        var shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Circle;
        shape.radius = 1f;
        shape.radiusThickness = 1f - innerRadius;
        shape.rotation = new Vector3(90f, 0f, 0f);

        // spin around the disc's axis and drift slowly inwards
        var velocity = ps.velocityOverLifetime;
        velocity.enabled = true;
        velocity.space = ParticleSystemSimulationSpace.Local;
        velocity.orbitalX = new ParticleSystem.MinMaxCurve(0f, 0f);
        velocity.orbitalY = new ParticleSystem.MinMaxCurve(spin * 0.7f, spin * 1.3f);
        velocity.orbitalZ = new ParticleSystem.MinMaxCurve(0f, 0f);
        velocity.radial = -0.03f;

        var fade = ps.colorOverLifetime;
        fade.enabled = true;
        var gradient = new Gradient();
        gradient.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                         new[] { new GradientAlphaKey(0f, 0f), new GradientAlphaKey(1f, 0.2f), new GradientAlphaKey(1f, 0.7f), new GradientAlphaKey(0f, 1f) });
        fade.color = gradient;

        var look = go.GetComponent<ParticleSystemRenderer>();
        look.sharedMaterial = material;
        look.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        look.receiveShadows = false;

        ps.Play();
        swirl = ps;
    }
}
