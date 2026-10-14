using UnityEngine;

public class VRRecenter : MonoBehaviour
{
    [Header("VR References")]
    [SerializeField] private Transform xrOrigin;
    [SerializeField] private Transform headsetCamera;

    [Header("Starting Position")]
    [SerializeField] private Transform startPoint;

    public void RecenterToStart()
    {
        if (xrOrigin == null ||
            headsetCamera == null ||
            startPoint == null)
        {
            Debug.LogError(
                "VRRecenter: Please assign all references."
            );
            return;
        }

        // Align the direction the player is facing
        Vector3 cameraForward = Vector3.ProjectOnPlane(
            headsetCamera.forward,
            Vector3.up
        ).normalized;

        Vector3 targetForward = Vector3.ProjectOnPlane(
            startPoint.forward,
            Vector3.up
        ).normalized;

        if (cameraForward.sqrMagnitude > 0.001f &&
            targetForward.sqrMagnitude > 0.001f)
        {
            float angle = Vector3.SignedAngle(
                cameraForward,
                targetForward,
                Vector3.up
            );

            // Rotate the XR Origin around the headset
            xrOrigin.RotateAround(
                headsetCamera.position,
                Vector3.up,
                angle
            );
        }

        // Align the player's horizontal position.
        // Preserve their tracked headset height.
        Vector3 offset = startPoint.position
                       - headsetCamera.position;

        offset.y = 0f;

        xrOrigin.position += offset;
    }
}