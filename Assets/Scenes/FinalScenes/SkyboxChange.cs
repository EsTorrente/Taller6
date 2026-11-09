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

    // Statics survive between Play sessions when "Reload Domain" is disabled in
    // Project Settings > Editor > Enter Play Mode Options, so clear them on every start.
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
    static void ResetStatics()
    {
        defaultSkybox = null;
        defaultSaved = false;
    }

    void OnEnable()
    {
        // Remember the scene's original skybox (Unity's Default-Skybox) the first time any
        // SkyboxChange is enabled, before it has been changed by us.
        if (!defaultSaved)
        {
            defaultSkybox = RenderSettings.skybox;
            defaultSaved = true;
        }

        // Only write to RenderSettings when something actually changes, so re-enabling an
        // object with the same skybox/fog doesn't trigger a needless environment refresh.
        Material target = useDefaultSkybox ? defaultSkybox : skybox;
        if (RenderSettings.skybox != target)
            RenderSettings.skybox = target;

        if (setFog && RenderSettings.fog != fogOn)
            RenderSettings.fog = fogOn;
    }
}