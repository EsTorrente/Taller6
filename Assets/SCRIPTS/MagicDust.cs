using System.Collections.Generic;
using UnityEngine;

// Small, subtle magic particles drifting down from every light figure under this object.
// One Particle System per figure is made when the scene starts, following the figure's body.
// A figure only sheds dust while it is switched on and on screen.
public class MagicDust : MonoBehaviour
{
    public Material material;
    [Tooltip("Particles per second, per figure")]
    public float rate = 6f;
    [Tooltip("Particle size (m)")]
    public float size = 0.015f;
    [Tooltip("Seconds each particle lives")]
    public float lifetime = 1.8f;
    [Tooltip("How fast they fall (m/s)")]
    public float fall = 0.25f;
    public Color color = new Color(1f, 0.72f, 0.35f);
    [Tooltip("Figures to shed dust from. Empty = every light figure under this object")]
    public SkinnedMeshRenderer[] figures;

    readonly List<(Renderer figure, ParticleSystem dust)> systems = new List<(Renderer, ParticleSystem)>();

    void Start()
    {
        var list = figures != null && figures.Length > 0 ? figures : GetComponentsInChildren<SkinnedMeshRenderer>(true);
        foreach (var figure in list)
            if (figure) systems.Add((figure, Make(figure)));
    }

    void Update()
    {
        foreach (var (figure, dust) in systems)
        {
            bool shown = figure && figure.enabled && figure.gameObject.activeInHierarchy && figure.isVisible;
            var emission = dust.emission;
            if (emission.enabled != shown) emission.enabled = shown;
        }
    }

    ParticleSystem Make(SkinnedMeshRenderer figure)
    {
        // a box around the body, on the bone the body's bounds are measured from, so it moves with the figure
        Transform at = figure.rootBone ? figure.rootBone : figure.transform;
        Bounds body = figure.localBounds;
        var go = new GameObject("MagicDust");
        go.transform.SetParent(at, false);
        go.transform.localPosition = body.center;

        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

        var main = ps.main;
        main.loop = true;
        main.startLifetime = new ParticleSystem.MinMaxCurve(lifetime * 0.6f, lifetime);
        main.startSpeed = 0f;
        main.startSize = new ParticleSystem.MinMaxCurve(size * 0.5f, size);
        main.startColor = color;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.scalingMode = ParticleSystemScalingMode.Shape;
        main.maxParticles = Mathf.CeilToInt(rate * lifetime) + 4;
        main.cullingMode = ParticleSystemCullingMode.Pause;

        var emission = ps.emission;
        emission.rateOverTime = rate;

        var shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Box;
        shape.scale = Vector3.Scale(body.size, new Vector3(0.6f, 0.9f, 0.6f));

        var velocity = ps.velocityOverLifetime;
        velocity.enabled = true;
        velocity.space = ParticleSystemSimulationSpace.World;
        velocity.x = new ParticleSystem.MinMaxCurve(-0.05f, 0.05f);
        velocity.y = new ParticleSystem.MinMaxCurve(-fall * 1.3f, -fall * 0.6f);
        velocity.z = new ParticleSystem.MinMaxCurve(-0.05f, 0.05f);

        // fade in quickly, then out
        var fade = ps.colorOverLifetime;
        fade.enabled = true;
        var gradient = new Gradient();
        gradient.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                         new[] { new GradientAlphaKey(0f, 0f), new GradientAlphaKey(1f, 0.15f), new GradientAlphaKey(0f, 1f) });
        fade.color = gradient;

        var look = go.GetComponent<ParticleSystemRenderer>();
        look.sharedMaterial = material;
        look.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        look.receiveShadows = false;

        ps.Play();
        return ps;
    }
}
