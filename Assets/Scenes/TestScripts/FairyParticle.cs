using UnityEngine;

[RequireComponent(typeof(Rigidbody))]
public class FairyFloat : MonoBehaviour
{
    [Header("Floating")]
    public float floatHeight = 0.12f;
    public float floatSpeed = 1.2f;
    public float swayAmount = 0.08f;
    public float swaySpeed = 0.7f;

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

    Vector3 startPosition;
    float randomOffset;

    float springWeight = 1f;
    float springTimer;

    void Start()
    {
        rb = GetComponent<Rigidbody>();

        startPosition = transform.position;
        randomOffset = Random.Range(0f, 100f);

        rb.useGravity = false;
    }

    void FixedUpdate()
    {
        float t = Time.time + randomOffset;

        Vector3 target =
            startPosition +
            Vector3.up * Mathf.Sin(t * floatSpeed) * floatHeight +
            Vector3.right * Mathf.Sin(t * swaySpeed) * swayAmount +
            Vector3.forward * Mathf.Cos(t * swaySpeed * 0.8f) * swayAmount;

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

        rb.AddForce(force - rb.linearVelocity * damping * springWeight, ForceMode.Acceleration);
    }

    void OnCollisionEnter(Collision collision)
    {
        ControllerVelocity velocity =
        collision.collider.GetComponentInParent<ControllerVelocity>();

        if (velocity == null)
            return;

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