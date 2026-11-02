using UnityEngine;

/// <summary>
/// Chooses which Light drives the rim light of "Custom/Painterly/WatercolorEnvironment" materials.
/// Set the material's "Rim Light Source" to "Custom Light" and drag any Light into the slot below.
/// Directional, point and spot lights work. Use only one of these components at a time (it sets global values).
/// </summary>
[ExecuteAlways]
[DisallowMultipleComponent]
public class PainterlyRimLight : MonoBehaviour
{
    [Tooltip("The light that produces the rim.")]
    public Light rimLight;

    static readonly int PosId = Shader.PropertyToID("_PainterlyRimLightPos");
    static readonly int ColorId = Shader.PropertyToID("_PainterlyRimLightColor");

    void OnEnable() => Apply();
    void OnValidate() => Apply();
    void LateUpdate() => Apply();   // follows the light when it moves

    void OnDisable()
    {
        Shader.SetGlobalVector(ColorId, Vector4.zero);   // no rim from the custom source
    }

    void Apply()
    {
        if (rimLight == null || !rimLight.isActiveAndEnabled)
        {
            Shader.SetGlobalVector(ColorId, Vector4.zero);
            return;
        }

        Transform t = rimLight.transform;

        // w = 0: directional (xyz = direction toward the light); w = 1: point/spot (xyz = position)
        Vector4 pos = rimLight.type == LightType.Directional
            ? new Vector4(-t.forward.x, -t.forward.y, -t.forward.z, 0f)
            : new Vector4(t.position.x, t.position.y, t.position.z, 1f);

        Color c = QualitySettings.activeColorSpace == ColorSpace.Linear ? rimLight.color.linear : rimLight.color;
        c *= rimLight.intensity;

        Shader.SetGlobalVector(PosId, pos);
        Shader.SetGlobalVector(ColorId, new Vector4(c.r, c.g, c.b, 1f));
    }
}
