using UnityEngine;

[RequireComponent(typeof(Rigidbody))]
public class FairyFloat : MonoBehaviour
{
    public enum MovementMode
    {
        FloatInPlace,
        OrbitObject
    }

    [Header("Movement Mode")]
    [Tooltip("Float in place, or orbit around a chosen object while floating.")]
    public MovementMode movementMode = MovementMode.FloatInPlace;

    [Header("Orbit (only used in Orbit Object mode)")]
    [Tooltip("The object to orbit around.")]
    public Transform orbitTarget;
    [Tooltip("Distance from the target.")]
    public float orbitRadius = 0.5f;
    [Tooltip("Degrees per second. Negative values orbit the other way.")]
    public float orbitSpeed = 60f;
    [Tooltip("Axis to orbit around (in the target's local space if 'Use Target Local Axis' is on).")]
    public Vector3 orbitAxis = Vector3.up;
    public bool useTargetLocalAxis = false;
    [Tooltip("Extra height offset above the target's position.")]
    public float orbitHeightOffset = 0f;

    [Header("Follow Smoothing (Orbit mode)")]
    [Tooltip("How smoothly the orbit center follows the target. Higher = smoother but more lag. 0 = no smoothing.")]
    public float followSmoothTime = 0.2f;

    [Header("Floating")]
    public float floatHeight = 0.12f;
    public float floatSpeed = 1.2f;
    public float swayAmount = 0.08f;
    public float swaySpeed = 0.7f;

    [Header("Facing")]
    [Tooltip("Rotate to face the active camera.")]
    public bool faceCamera = true;
    [Tooltip("Only rotate around the Y axis (stays upright).")]
    public bool yAxisOnly = false;
    [Tooltip("The rotation at which the object faces the camera (its base rotation).")]
    public Vector3 baseRotation = new Vector3(90f, 180f, 0f);

    [Header("Return")]
    public float returnForce = 8f;
    public float damping = 3f;

    [Header("Hit Feel")]
    public float hitMultiplier = 3f;
    public float maxHitVelocity = 6f;
    public float ignoreSpringTime = 0.25f;

    [Header("Controller Hit")]
    public float minControllerSpeed = 0.2f;
    public float maxControllerSpeed = 4f;

    public float minPush = 0.5f;
    public float maxPush = 8f;

    public AnimationCurve pushCurve =
        AnimationCurve.EaseInOut(0, 0, 1, 1);

    Rigidbody rb;
    Camera cam;

    Vector3 startPosition;
    float randomOffset;

    float orbitAngle; // current angle in degrees

    // Smoothed orbit center (so jerky target movement doesn't jerk the fairy)
    Vector3 smoothedCenter;
    Vector3 centerVelocity;

    // For feed-forward damping (fairy damps against the target's velocity, not zero)
    Vector3 lastTargetPos;
    Vector3 targetVelocity;
    bool hasLastTarget;

    float springWeight = 1f;
    float springTimer;

    void Start()
    {
        rb = GetComponent<Rigidbody>();

        startPosition = transform.position;
        randomOffset = Random.Range(0f, 100f);

        rb.useGravity = false;
        rb.freezeRotation = true; // hits shouldn't spin it

        // Smooths the visual movement between physics steps (fixes stepping/jitter)
        rb.interpolation = RigidbodyInterpolation.Interpolate;

        if (orbitTarget != null)
            smoothedCenter = orbitTarget.position;

        InitOrbitAngle();
    }

    // Start the orbit from wherever the fairy currently is, so it doesn't snap.
    void InitOrbitAngle()
    {
        if (orbitTarget == null) return;

        Vector3 axis = GetOrbitAxis();
        Vector3 offset = Vector3.ProjectOnPlane(transform.position - orbitTarget.position, axis);

        if (offset.sqrMagnitude < 0.0001f)
        {
            orbitAngle = 0f;
            return;
        }

        Vector3 reference = GetOrbitReference(axis);
        orbitAngle = Vector3.SignedAngle(reference, offset, axis);
    }

    Vector3 GetOrbitAxis()
    {
        Vector3 axis = orbitAxis.sqrMagnitude < 0.0001f ? Vector3.up : orbitAxis.normalized;
        if (useTargetLocalAxis && orbitTarget != null)
            axis = orbitTarget.TransformDirection(axis);
        return axis.normalized;
    }

    // A stable vector perpendicular to the axis, used as angle 0.
    Vector3 GetOrbitReference(Vector3 axis)
    {
        Vector3 reference = Vector3.Cross(axis, Vector3.up);
        if (reference.sqrMagnitude < 0.0001f)
            reference = Vector3.Cross(axis, Vector3.right);
        return reference.normalized;
    }

    Vector3 GetBasePosition()
    {
        if (movementMode == MovementMode.OrbitObject && orbitTarget != null)
        {
            Vector3 axis = GetOrbitAxis();
            Vector3 reference = GetOrbitReference(axis);
            Vector3 radial = Quaternion.AngleAxis(orbitAngle, axis) * reference;

            return smoothedCenter
                   + radial * orbitRadius
                   + axis * orbitHeightOffset;
        }

        return startPosition;
    }

    void FixedUpdate()
    {
        float t = Time.time + randomOffset;

        bool orbiting = movementMode == MovementMode.OrbitObject && orbitTarget != null;

        if (orbiting)
        {
            orbitAngle = Mathf.Repeat(orbitAngle + orbitSpeed * Time.fixedDeltaTime, 360f);

            if (followSmoothTime > 0.0001f)
                smoothedCenter = Vector3.SmoothDamp(
                    smoothedCenter, orbitTarget.position, ref centerVelocity,
                    followSmoothTime, Mathf.Infinity, Time.fixedDeltaTime);
            else
                smoothedCenter = orbitTarget.position;
        }

        Vector3 target =
            GetBasePosition() +
            Vector3.up * Mathf.Sin(t * floatSpeed) * floatHeight +
            Vector3.right * Mathf.Sin(t * swaySpeed) * swayAmount +
            Vector3.forward * Mathf.Cos(t * swaySpeed * 0.8f) * swayAmount;

        // Velocity of the moving target, so the fairy matches it instead of lagging behind
        if (hasLastTarget && Time.fixedDeltaTime > 0f)
            targetVelocity = (target - lastTargetPos) / Time.fixedDeltaTime;
        else
            targetVelocity = Vector3.zero;
        lastTargetPos = target;
        hasLastTarget = true;

        // Delay the spring after being hit
        if (springTimer > 0)
        {
            springTimer -= Time.fixedDeltaTime;
            springWeight = 0;
        }
        else
        {
            springWeight = Mathf.MoveTowards(springWeight, 1f, Time.fixedDeltaTime * 3f);
        }

        Vector3 force = (target - rb.position) * returnForce * springWeight;

        // In orbit mode, damp relative to the target's motion so it follows smoothly
        Vector3 referenceVelocity = orbiting ? targetVelocity : Vector3.zero;
        Vector3 dampingForce = (rb.linearVelocity - referenceVelocity) * damping * springWeight;

        rb.AddForce(force - dampingForce, ForceMode.Acceleration);
    }

    void LateUpdate()
    {
        if (!faceCamera) return;

        // Find the active camera (re-check if it was disabled or destroyed)
        if (cam == null || !cam.isActiveAndEnabled)
            cam = Camera.main;
        if (cam == null) return;

        // Direction pointing AWAY from the camera. The base rotation (90, 180, 0)
        // is the pose where the object's visible face points back along -Z,
        // so aligning +Z with this direction turns that face toward the camera.
        Vector3 dir = transform.position - cam.transform.position;
        if (yAxisOnly) dir.y = 0f;
        if (dir.sqrMagnitude < 0.0001f) return;

        transform.rotation = Quaternion.LookRotation(dir, Vector3.up) * Quaternion.Euler(baseRotation);
    }

    void OnCollisionEnter(Collision collision)
    {
        Transform hitTransform = collision.collider.transform;
        string path = hitTransform.name;
        while (hitTransform.parent != null)
        {
            hitTransform = hitTransform.parent;
            path = hitTransform.name + "/" + path;
        }

        Debug.Log(
            $"Hit by {collision.collider.GetType().Name} at {path} | " +
            $"isTrigger={collision.collider.isTrigger} | " +
            $"rigidbody={(collision.rigidbody != null ? collision.rigidbody.name : "none")}",
            collision.collider);

        ControllerVelocity velocity =
            collision.collider.GetComponentInParent<ControllerVelocity>();

        if (velocity == null)
        {
            Debug.Log("No ControllerVelocity found on or above that collider");
            return;
        }

        float controllerSpeed = velocity.Velocity.magnitude;
        Debug.Log(controllerSpeed);

        if (controllerSpeed < minControllerSpeed)
            return;

        ContactPoint contact = collision.GetContact(0);

        // Push away from where the hand touched
        Vector3 awayFromContact = (transform.position - contact.point).normalized;

        Vector3 direction =
            (awayFromContact * 0.5f + velocity.Velocity.normalized * 0.5f).normalized;

        // Convert controller speed to a 0-1 value
        float t = Mathf.InverseLerp(
            minControllerSpeed,
            maxControllerSpeed,
            controllerSpeed);

        // Shape the response with the curve
        t = pushCurve.Evaluate(t);

        // Calculate final push strength
        float pushStrength = Mathf.Lerp(
            minPush,
            maxPush,
            t);

        // Apply the impulse
        rb.AddForce(direction * pushStrength, ForceMode.Impulse);

        // Limit maximum speed
        if (rb.linearVelocity.magnitude > maxHitVelocity)
            rb.linearVelocity = rb.linearVelocity.normalized * maxHitVelocity;

        springTimer = ignoreSpringTime;
    }
}