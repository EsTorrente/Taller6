
using UnityEngine;

public class EnvironmentReflectionIntensity : MonoBehaviour
{
    [Range(0f, 2f)]
    public float intensityMultiplier = 1f;

    void Update()
    {
        RenderSettings.reflectionIntensity = intensityMultiplier;
    }
}
