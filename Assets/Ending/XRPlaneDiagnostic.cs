
using UnityEngine;

public class XRPlaneDiagnostic : MonoBehaviour
{
    public Transform xrCamera;

    void Update()
    {
        if (xrCamera == null) return;

        Vector3 relativePosition =
            xrCamera.InverseTransformPoint(transform.position);

        Debug.Log(
            $"Plane World Position: {transform.position}\n" +
            $"Camera World Position: {xrCamera.position}\n" +
            $"Relative Position: {relativePosition}"
        );
    }
}
