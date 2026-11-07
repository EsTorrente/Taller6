using UnityEngine;
using UnityEngine.XR.Hands;

/// <summary>
/// Creates a physical palm collider on every XR Hand Skeleton Driver found under this object.
/// Each collider gets a kinematic Rigidbody and a ControllerVelocity so FairyFloat can read the hand's speed.
///
/// Put this on the XR Origin Hands (XR Rig) root (or on each hand object).
/// </summary>
public class HandPalmColliders : MonoBehaviour
{
    [Header("Collider")]
    public float radius = 0.05f;
    public Vector3 localOffset = Vector3.zero;

    [Header("Debug")]
    public bool showLogs = true;

    const string ColliderName = "PalmCollider";

    void Start()
    {
        var drivers = GetComponentsInChildren<XRHandSkeletonDriver>(true);

        if (drivers.Length == 0 && showLogs)
            Debug.LogWarning("HandPalmColliders: no XRHandSkeletonDriver found under this object.", this);

        foreach (var driver in drivers)
        {
            Transform palm = FindPalm(driver);

            if (palm == null)
            {
                if (showLogs)
                    Debug.LogWarning($"HandPalmColliders: no Palm joint found on {driver.name}.", driver);
                continue;
            }

            if (palm.Find(ColliderName) != null)
                continue; // already created

            CreatePalmCollider(palm);
        }
    }

    Transform FindPalm(XRHandSkeletonDriver driver)
    {
        // Preferred: use the joint references assigned on the skeleton driver
        foreach (var reference in driver.jointTransformReferences)
        {
            if (reference.xrHandJointID == XRHandJointID.Palm)
                return reference.jointTransform;
        }

        // Fallback: look for a transform with "palm" in its name
        foreach (var child in driver.GetComponentsInChildren<Transform>(true))
        {
            if (child.name.ToLower().Contains("palm"))
                return child;
        }

        return null;
    }

    void CreatePalmCollider(Transform palm)
    {
        var go = new GameObject(ColliderName);
        go.transform.SetParent(palm, false);
        go.transform.localPosition = localOffset;

        var sphere = go.AddComponent<SphereCollider>();
        sphere.radius = radius;
        sphere.isTrigger = false;

        var rb = go.AddComponent<Rigidbody>();
        rb.isKinematic = true;
        rb.useGravity = false;
        rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative;

        go.AddComponent<ControllerVelocity>();

        if (showLogs)
            Debug.Log($"HandPalmColliders: created palm collider on {palm.name}", palm);
    }
}
