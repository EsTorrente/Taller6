using UnityEngine;

// Sets the skybox and fog for a scene section when this object is turned on
// by an Activation Track in DirectorCinemTimeline.
public class SkyboxChange : MonoBehaviour
{
    [Tooltip("Leave empty and tick 'Use Default Skybox' for E1.")]
    public Material skybox;
    public bool useDefaultSkybox = false;

    [Header("Fog")]
    public bool setFog = true;
    public bool fogOn = false;

    static Material defaultSkybox;
    static bool defaultSaved;

    void Awake()
    {
        // Remember the scene's original skybox (Unity's Default-Skybox)
        if (!defaultSaved) { defaultSkybox = RenderSettings.skybox; defaultSaved = true; }
    }

    void OnEnable()
    {
        if (!defaultSaved) { defaultSkybox = RenderSettings.skybox; defaultSaved = true; }
        RenderSettings.skybox = useDefaultSkybox ? defaultSkybox : skybox;
        if (setFog) RenderSettings.fog = fogOn;
    }
}