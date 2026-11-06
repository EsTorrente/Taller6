using UnityEngine;
using UnityEngine.Events;
using UnityEngine.Playables;
using UnityEngine.XR.Interaction.Toolkit;
using UnityEngine.XR.Interaction.Toolkit.Interactables;

/// <summary>
/// A small object that floats in space. When it is grabbed (hand tracking via XR Interaction Toolkit),
/// it plays a Timeline (PlayableDirector).
///
/// Requires XR Interaction Toolkit 3.x (Unity 6). Works with the XR Hands "Near-Far Interactor" / Grab Interactor.
/// </summary>
[RequireComponent(typeof(Rigidbody))]
[RequireComponent(typeof(XRGrabInteractable))]
public class FairyGrabTimeline : MonoBehaviour
{
    public enum ReleaseBehavior
    {
        ReturnToStart,      // floats back to where it began
        FloatWhereReleased, // keeps floating at the place you let go
        Disable             // object disappears when released
    }

    [Header("Timeline")]
    [Tooltip("The Timeline to play when the object is grabbed.")]
    public PlayableDirector director;
    [Tooltip("Only trigger the Timeline the first time it is grabbed.")]
    public bool playOnce = true;
    [Tooltip("Restart the Timeline from the beginning when triggered.")]
    public bool restartFromBeginning = true;
    public float delayBeforePlay = 0f;

    [Header("Floating")]
    public float floatHeight = 0.12f;
    public float floatSpeed = 1.2f;
    public float swayAmount = 0.08f;
    public float swaySpeed = 0.7f;

    [Header("Spring")]
    public float returnForce = 8f;
    public float damping = 3f;
    [Tooltip("How fast the spring fades back in after release (per second).")]
    public float springRecoverSpeed = 3f;

    [Header("When Released")]
    public ReleaseBehavior releaseBehavior = ReleaseBehavior.ReturnToStart;

    [Header("Events")]
    public UnityEvent onGrabbed;
    public UnityEvent onReleased;

    Rigidbody rb;
    XRGrabInteractable grab;

    Vector3 startPosition;
    float randomOffset;
    float springWeight = 1f;

    bool wasSelected;
    bool hasTriggered;

    void Awake()
    {
        rb = GetComponent<Rigidbody>();
        grab = GetComponent<XRGrabInteractable>();

        rb.useGravity = false;

        // Make it follow the hand directly and never get thrown when released
        grab.movementType = XRBaseInteractable.MovementType.Instantaneous;
        grab.throwOnDetach = false;
    }

    void Start()
    {
        startPosition = transform.position;
        randomOffset = Random.Range(0f, 100f);
    }

    void OnEnable()
    {
        grab.selectEntered.AddListener(OnGrab);
        grab.selectExited.AddListener(OnRelease);
    }

    void OnDisable()
    {
        grab.selectEntered.RemoveListener(OnGrab);
        grab.selectExited.RemoveListener(OnRelease);
    }

    void FixedUpdate()
    {
        // While held, the XR Interaction Toolkit moves the object. Don't fight it.
        if (grab.isSelected)
        {
            wasSelected = true;
            return;
        }

        // First physics frame after being let go: clear any leftover velocity
        if (wasSelected)
        {
            wasSelected = false;
            rb.linearVelocity = Vector3.zero;
            rb.angularVelocity = Vector3.zero;
            springWeight = 0f;
        }

        springWeight = Mathf.MoveTowards(springWeight, 1f, Time.fixedDeltaTime * springRecoverSpeed);

        float t = Time.time + randomOffset;

        Vector3 target =
            startPosition +
            Vector3.up * Mathf.Sin(t * floatSpeed) * floatHeight +
            Vector3.right * Mathf.Sin(t * swaySpeed) * swayAmount +
            Vector3.forward * Mathf.Cos(t * swaySpeed * 0.8f) * swayAmount;

        Vector3 force = (target - rb.position) * returnForce * springWeight;
        rb.AddForce(force - rb.linearVelocity * damping * springWeight, ForceMode.Acceleration);
    }

    void OnGrab(SelectEnterEventArgs args)
    {
        Debug.Log("Fairy grabbed", this);
        onGrabbed?.Invoke();

        if (playOnce && hasTriggered)
            return;

        hasTriggered = true;

        if (delayBeforePlay > 0f)
            Invoke(nameof(PlayTimeline), delayBeforePlay);
        else
            PlayTimeline();
    }

    void OnRelease(SelectExitEventArgs args)
    {
        onReleased?.Invoke();

        switch (releaseBehavior)
        {
            case ReleaseBehavior.FloatWhereReleased:
                startPosition = transform.position;
                break;

            case ReleaseBehavior.Disable:
                gameObject.SetActive(false);
                break;

            case ReleaseBehavior.ReturnToStart:
            default:
                break;
        }
    }

    void PlayTimeline()
    {
        if (director == null)
        {
            Debug.LogWarning("FairyGrabTimeline: no PlayableDirector assigned.", this);
            return;
        }

        if (restartFromBeginning)
            director.time = 0;

        director.Play();
    }
}
