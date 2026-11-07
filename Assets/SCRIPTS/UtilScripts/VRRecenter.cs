using System.Collections;
using System.Collections.Generic;
using Unity.XR.CoreUtils;
using UnityEngine;
using UnityEngine.XR;

/// <summary>
/// Puts the player's HEAD at a chosen spot in the scene (regardless of their real height or
/// where they stand in their room) and turns them to face a chosen direction.
/// Put this on any object, assign the XR Origin and a spawn point, done.
/// </summary>
public class VRRecenter : MonoBehaviour
{
    [Header("References")]
    [Tooltip("The XR Origin in your scene. Found automatically if left empty.")]
    [SerializeField] private XROrigin xrOrigin;

    [Tooltip("Empty object marking where the player's head should be and which way they should face (its blue Z axis).")]
    [SerializeField] private Transform spawnPoint;

    [Header("Behaviour")]
    [Tooltip("Seconds to wait after the scene loads so the headset is tracking before we move anything.")]
    [SerializeField] private float delay = 1f;

    [Tooltip("Use Device (eye level) tracking so every user's eyes land on the spawn point, whatever their height.")]
    [SerializeField] private bool useDeviceTrackingOrigin = true;

    [Tooltip("Also ask the XR runtime to recenter (same as the old script did).")]
    [SerializeField] private bool recenterRuntime = true;

    [Tooltip("Rotate the player to face the spawn point's forward direction.")]
    [SerializeField] private bool matchFacing = true;

    private void OnEnable()
    {
        StartCoroutine(RepositionAfterDelay());
    }

    private IEnumerator RepositionAfterDelay()
    {
        yield return new WaitForSeconds(delay);
        yield return Reposition();
    }

    /// <summary>Can also be called from a button, a menu, or after a scene change.</summary>
    public IEnumerator Reposition()
    {
        if (xrOrigin == null)
            xrOrigin = FindFirstObjectByType<XROrigin>();

        if (xrOrigin == null || spawnPoint == null)
        {
            Debug.LogWarning("VRRecenter: assign an XR Origin and a Spawn Point.");
            yield break;
        }

        // 1. Eye-level tracking: the headset itself is the reference, so height no longer matters.
        if (useDeviceTrackingOrigin)
        {
            xrOrigin.RequestedTrackingOriginMode = XROrigin.TrackingOriginMode.Device;
            yield return null; // let the mode change apply before we measure the camera
        }

        // 2. Optional runtime recenter (resets the real-world reference to where the user is now).
        if (recenterRuntime)
        {
            var subsystems = new List<XRInputSubsystem>();
            SubsystemManager.GetSubsystems(subsystems);

            foreach (XRInputSubsystem subsystem in subsystems)
            {
                if (!subsystem.running)
                    continue;

                bool success = subsystem.TryRecenter();
                Debug.Log(success
                    ? "VR recentered successfully!"
                    : "This XR runtime does not support recentering.");
            }

            yield return null; // wait a frame so the new reference is used
        }

        // 3. Rotate first (about the camera), THEN move, because rotating can shift the camera.
        if (matchFacing)
        {
            Vector3 flatForward = Vector3.ProjectOnPlane(spawnPoint.forward, Vector3.up);
            if (flatForward.sqrMagnitude < 0.0001f)
                flatForward = Vector3.forward;

            xrOrigin.MatchOriginUpCameraForward(Vector3.up, flatForward.normalized);
        }

        // 4. Move the rig so the CAMERA (the player's head) ends up exactly on the spawn point.
        xrOrigin.MoveCameraToWorldLocation(spawnPoint.position);
    }
}