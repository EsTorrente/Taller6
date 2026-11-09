using System.Collections;
using System.Collections.Generic;
using Unity.XR.CoreUtils;
using UnityEngine;
using UnityEngine.XR;

/// <summary>
/// Puts the player's HEAD at a chosen spot in the scene (regardless of their real height or
/// where they stand in their room) and turns them to face a chosen direction.
/// Only the head's yaw (left/right turn) is used: pitch and roll (tilting) are ignored.
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

    [Tooltip("Rotate the player to face the spawn point's forward direction (yaw only, head tilt is ignored).")]
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

        // 3. Rotate (yaw only) around the camera, THEN move, because rotating can shift the camera.
        if (matchFacing && xrOrigin.Camera != null)
        {
            Vector3 up = xrOrigin.Origin.transform.up;

            // Where the spawn point wants the player to face, flattened onto the horizontal plane.
            Vector3 desiredForward = Vector3.ProjectOnPlane(spawnPoint.forward, up);
            if (desiredForward.sqrMagnitude < 0.0001f)
                desiredForward = Vector3.ProjectOnPlane(Vector3.forward, up);

            // Where the head is actually facing, ignoring pitch and roll.
            Vector3 headForward = GetHeadYawForward(xrOrigin.Camera.transform, up);

            float yawDelta = Vector3.SignedAngle(headForward, desiredForward, up);
            xrOrigin.RotateAroundCameraUsingOriginUp(yawDelta);
        }

        // 4. Move the rig so the CAMERA (the player's head) ends up exactly on the spawn point.
        xrOrigin.MoveCameraToWorldLocation(spawnPoint.position);
    }

    /// <summary>
    /// Returns the horizontal direction the head is facing, unaffected by tilting (pitch/roll).
    /// </summary>
    private static Vector3 GetHeadYawForward(Transform head, Vector3 up)
    {
        Vector3 flat = Vector3.ProjectOnPlane(head.forward, up);

        // Looking almost straight up or down: forward is unreliable, so use the head's "up"
        // direction instead (it points forward when looking down, backward when looking up).
        if (flat.sqrMagnitude < 0.05f)
        {
            Vector3 alt = Vector3.ProjectOnPlane(head.up, up);
            flat = Vector3.Dot(head.forward, up) < 0f ? alt : -alt;
        }

        return flat.normalized;
    }
}