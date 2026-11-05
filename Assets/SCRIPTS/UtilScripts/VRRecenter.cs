
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR;

public class VRRecenter : MonoBehaviour
{
    [SerializeField] private float delay = 1f;

    private IEnumerator Start()
    {
        yield return new WaitForSeconds(delay);

        List<XRInputSubsystem> subsystems =
            new List<XRInputSubsystem>();

        SubsystemManager.GetSubsystems(subsystems);

        foreach (XRInputSubsystem subsystem in subsystems)
        {
            if (subsystem.running)
            {
                bool success = subsystem.TryRecenter();

                Debug.Log(success
                    ? "VR recentered successfully!"
                    : "This XR runtime does not support recentering.");
            }
        }
    }
}
