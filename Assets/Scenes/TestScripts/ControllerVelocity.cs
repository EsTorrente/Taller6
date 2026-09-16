using UnityEngine;

public class ControllerVelocity : MonoBehaviour
{
    public Vector3 Velocity { get; private set; }

    Vector3 lastPosition;

    void Start()
    {
        lastPosition = transform.position;
    }

    void Update()
    {
        Velocity = (transform.position - lastPosition) / Time.deltaTime;
        lastPosition = transform.position;
    }
}