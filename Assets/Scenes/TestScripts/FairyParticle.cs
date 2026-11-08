using UnityEngine;

// Runs after most scripts so the tracked object has already moved this frame.
[DefaultExecutionOrder(100)]
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
    [Tooltip("The object to orbit. The fairy is carried along with it like a child.")]
    public Transform orbitTarget;
    [Tooltip("Distance from the target.")]
    public float orbitRadius = 0.5f;
    [Tooltip("Degrees per second. Negative values orbit the other way.")]
    public float orbitSpeed = 60f;
    [Tooltip("Axis to orbit around (in the target's local space if 'Use Target Local Axis' is on).")]
    public Vector3 orbitAxis = Vector3.up;
    public bool useTargetLocalAxis = false;
    [Tooltip("Extra height offset along the orbit axis.")]
    public float orbitHeightOffset = 0f;

    [Header("Target Safety (Orbit mode)")]
    [Tooltip("Stops the fairy's collider from bumping the orbit target. Overlapping colliders can push the target around and cause glitching.")]
    public bool ignoreTargetCollisions = true;
    [Tooltip("If the target has a Rigidbody with Interpolation off, switch it on. A physics-moved target otherwise visibly steps at the physics rate.")]
    public bool fixTargetInterpolation = true;

    [Header("Debug")]
    public bool debugLogs = false;

    [Header("Grab / Release")]
    [Tooltip("Seconds the fairy takes to ease back to its floating spot after you let go. Higher = gentler return.")]
    public float releaseRampTime = 0.8f;
    [Tooltip("Short pause (seconds) after letting go before the return starts, so it drifts a moment from where you released it.")]
    public float releaseReturnDelay = 0.1f;
    [Tooltip("How much of your hand's motion carries into the fairy when you let go. 0 = none.")]
    public float throwInfluence = 1f;

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

    // The fairy's float/bounce is simulated in the "anchor's frame":
    //   world position = anchor position + localOffset
    // The anchor is the orbit target (or the start position in Float In Place mode).
    // Because the spring only ever sees localOffset, moving the anchor carries the
    // fairy along rigidly and never disturbs its float or bounce-back.
    Vector3 localOffset;
    Vector3 prevLocalOffset; // for render interpolation
    Vector3 localVelocity;

    Vector3 lastLocalTarget;
    bool hasLastTarget;

    Transform currentAnchor;
    bool wasOrbiting;
    Collider[] ignoredColliders;

    // Grab handling
    bool manualHeld;
    bool isHeld;
    Behaviour selectedSource;
    System.Func<bool> selectedGetter;
    Vector3 heldLastOffset;
    Vector3 heldVelocity;
    float rampRate = 3f;

    float springWeight = 1f;
    float springTimer;

    bool IsOrbiting => movementMode == MovementMode.OrbitObject && orbitTarget != null;

    void Start()
    {
        rb = GetComponent<Rigidbody>();

        startPosition = transform.position;
        randomOffset = Random.Range(0f, 100f);

        rb.useGravity = false;
        rb.freezeRotation = true; // hits shouldn't spin it

        // We position the transform ourselves every frame, so Unity's rigidbody
        // interpolation must be off or the two will fight (that causes jitter).
        rb.interpolation = RigidbodyInterpolation.None;

        FindGrabSource();
        SyncAnchor();
    }

    Vector3 GetAnchorPosition()
    {
        return IsOrbiting ? orbitTarget.position : startPosition;
    }

    // Re-anchors without any snapping when the mode or target changes.
    void SyncAnchor()
    {
        bool orbiting = IsOrbiting;
        Transform anchor = orbiting ? orbitTarget : null;

        if (anchor == currentAnchor && orbiting == wasOrbiting)
            return;

        ReleaseIgnoredColliders();

        currentAnchor = anchor;
        wasOrbiting = orbiting;

        if (orbiting)
        {
            InitOrbitAngle();
            PrepareTarget();
        }

        localOffset = transform.position - GetAnchorPosition();
        prevLocalOffset = localOffset;
        hasLastTarget = false;
    }

    void PrepareTarget()
    {
        if (ignoreTargetCollisions)
        {
            ignoredColliders = orbitTarget.GetComponentsInChildren<Collider>();
            SetIgnore(ignoredColliders, true);
        }

        if (fixTargetInterpolation)
        {
            Rigidbody targetBody = orbitTarget.GetComponentInParent<Rigidbody>();
            if (targetBody != null && targetBody.interpolation == RigidbodyInterpolation.None)
                targetBody.interpolation = RigidbodyInterpolation.Interpolate;
        }
    }

    void ReleaseIgnoredColliders()
    {
        if (ignoredColliders == null) return;
        SetIgnore(ignoredColliders, false);
        ignoredColliders = null;
    }

    void SetIgnore(Collider[] others, bool ignore)
    {
        Collider[] mine = GetComponentsInChildren<Collider>();
        foreach (Collider other in others)
        {
            if (other == null) continue;
            foreach (Collider m in mine)
                if (m != other)
                    Physics.IgnoreCollision(m, other, ignore);
        }
    }

    // Start the orbit from wherever the fairy currently is, so it doesn't snap.
    void InitOrbitAngle()
    {
        Vector3 axis = GetOrbitAxis();
        Vector3 offset = Vector3.ProjectOnPlane(transform.position - orbitTarget.position, axis);

        if (offset.sqrMagnitude < 0.0001f)
        {
            orbitAngle = 0f;
            return;
        }

        orbitAngle = Vector3.SignedAngle(GetOrbitReference(axis), offset, axis);
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

    // Where on the orbit circle the fairy wants to be, relative to the anchor.
    Vector3 GetOrbitLocalTarget()
    {
        Vector3 axis = GetOrbitAxis();
        Vector3 radial = Quaternion.AngleAxis(orbitAngle, axis) * GetOrbitReference(axis);
        return radial * orbitRadius + axis * orbitHeightOffset;
    }

    // ---------- Grab / release ----------

    // Optional manual hooks, for grab systems that aren't detected automatically.
    // Hook these to your grab object's "grabbed" / "released" events.
    public void Grabbed() { manualHeld = true; }
    public void Released() { manualHeld = false; }

    // Auto-detects XR Interaction Toolkit grabs (any component with a bool "isSelected").
    void FindGrabSource()
    {
        foreach (Behaviour b in GetComponentsInParent<Behaviour>())
        {
            if (b == this) continue;

            System.Reflection.PropertyInfo pi = b.GetType().GetProperty(
                "isSelected",
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);

            if (pi != null && pi.PropertyType == typeof(bool) && pi.CanRead)
            {
                selectedSource = b;
                selectedGetter = (System.Func<bool>)System.Delegate.CreateDelegate(
                    typeof(System.Func<bool>), b, pi.GetGetMethod());
                return;
            }
        }
    }

    bool DetectHeld()
    {
        if (manualHeld) return true;
        if (rb != null && rb.isKinematic) return true; // many grab systems make it kinematic while held
        if (selectedGetter != null && selectedSource != null) return selectedGetter();
        return false;
    }

    void UpdateHeldState()
    {
        bool held = DetectHeld();
        if (held == isHeld) return;

        isHeld = held;

        if (isHeld)
        {
            localVelocity = Vector3.zero;
            heldVelocity = Vector3.zero;
            heldLastOffset = transform.position - GetAnchorPosition();
            hasLastTarget = false;
        }
        else
        {
            // Let go: carry on from exactly where it was released
            ResumeFromCurrentPosition(heldVelocity * throwInfluence);
        }
    }

    // Start the float/bounce simulation from wherever the fairy is right now,
    // and ease the spring back in so it glides home instead of snapping.
    void ResumeFromCurrentPosition(Vector3 velocity)
    {
        localOffset = transform.position - GetAnchorPosition();
        prevLocalOffset = localOffset;
        localVelocity = Vector3.ClampMagnitude(velocity, maxHitVelocity);
        hasLastTarget = false;

        springWeight = 0f;
        springTimer = releaseReturnDelay;
        rampRate = 1f / Mathf.Max(0.05f, releaseRampTime);
    }

    // While held, just follow along and measure how the hand is moving.
    void TrackHeld()
    {
        Vector3 offset = transform.position - GetAnchorPosition();
        float dt = Time.deltaTime;

        if (dt > 0f)
        {
            Vector3 v = (offset - heldLastOffset) / dt;
            float k = 1f - Mathf.Exp(-20f * dt);
            heldVelocity = Vector3.Lerp(heldVelocity, v, k);
        }

        heldLastOffset = offset;
        localOffset = offset;
        prevLocalOffset = offset;
    }

    void FixedUpdate()
    {
        SyncAnchor();
        UpdateHeldState();
        if (isHeld) return; // the grab system is in control

        float dt = Time.fixedDeltaTime;
        float t = Time.time + randomOffset;
        bool orbiting = IsOrbiting;

        prevLocalOffset = localOffset;

        // Where the fairy wants to be, relative to its anchor
        Vector3 localTarget =
            Vector3.up * Mathf.Sin(t * floatSpeed) * floatHeight +
            Vector3.right * Mathf.Sin(t * swaySpeed) * swayAmount +
            Vector3.forward * Mathf.Cos(t * swaySpeed * 0.8f) * swayAmount;

        if (orbiting)
        {
            orbitAngle = Mathf.Repeat(orbitAngle + orbitSpeed * dt, 360f);
            localTarget += GetOrbitLocalTarget();
        }

        // Delay the spring after being hit
        if (springTimer > 0)
        {
            springTimer -= dt;
            springWeight = 0;
        }
        else
        {
            springWeight = Mathf.MoveTowards(springWeight, 1f, dt * rampRate);
        }

        // In orbit mode, damp relative to the moving orbit point so it doesn't lag behind it
        Vector3 targetVelocity = Vector3.zero;
        if (orbiting && hasLastTarget)
            targetVelocity = (localTarget - lastLocalTarget) / dt;
        lastLocalTarget = localTarget;
        hasLastTarget = true;

        // Spring + damping, all in the local frame
        Vector3 acceleration =
            (localTarget - localOffset) * returnForce * springWeight
            - (localVelocity - targetVelocity) * damping * springWeight;

        localVelocity += acceleration * dt;
        localOffset += localVelocity * dt;

        // Keep the physics body in sync so collisions still register.
        // Its own velocity is ignored; the local simulation above is the real motion.
        rb.position = GetAnchorPosition() + localOffset;
        rb.linearVelocity = Vector3.zero;
        rb.angularVelocity = Vector3.zero;
    }

    void OnEnable()
    {
        Application.onBeforeRender += ApplyPose;

        // Re-enabled after being switched off (e.g. during a grab): glide back instead of snapping
        if (rb != null)
        {
            SyncAnchor();
            ResumeFromCurrentPosition(Vector3.zero);
        }
    }

    void OnDisable()
    {
        Application.onBeforeRender -= ApplyPose;
        ReleaseIgnoredColliders();
        currentAnchor = null;
        wasOrbiting = false;
        isHeld = false;
    }

    void LateUpdate()
    {
        SyncAnchor();
        UpdateHeldState();

        if (isHeld)
            TrackHeld();

        ApplyPose();
    }

    // Runs in LateUpdate AND again right before rendering, so tracked objects
    // (VR controllers etc.) that update their pose late are still followed exactly.
    void ApplyPose()
    {
        if (rb == null) return;

        // Blend the local offset between physics steps (smooth at any frame rate),
        // then attach it to the anchor's CURRENT position, exactly like a child object.
        if (!isHeld)
        {
            float alpha = Time.fixedDeltaTime > 0f
                ? Mathf.Clamp01((Time.time - Time.fixedTime) / Time.fixedDeltaTime)
                : 1f;

            Vector3 renderOffset = Vector3.Lerp(prevLocalOffset, localOffset, alpha);
            transform.position = GetAnchorPosition() + renderOffset;
        }

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
        if (isHeld) return;

        if (debugLogs)
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
        }

        ControllerVelocity velocity =
            collision.collider.GetComponentInParent<ControllerVelocity>();

        if (velocity == null)
        {
            if (debugLogs) Debug.Log("No ControllerVelocity found on or above that collider");
            return;
        }

        float controllerSpeed = velocity.Velocity.magnitude;
        if (debugLogs) Debug.Log(controllerSpeed);

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

        // Apply the impulse to the local velocity (same result as an Impulse force on the rigidbody)
        localVelocity += direction * pushStrength / Mathf.Max(rb.mass, 0.0001f);

        // Limit maximum speed
        if (localVelocity.magnitude > maxHitVelocity)
            localVelocity = localVelocity.normalized * maxHitVelocity;

        springTimer = ignoreSpringTime;
        rampRate = 3f;
    }
}