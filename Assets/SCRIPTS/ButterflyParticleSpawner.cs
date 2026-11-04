using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ButterflyParticleSpawner : MonoBehaviour
{
    [Header("Renderer / Prefab")]
    [Tooltip("Drag your animated Butterfly Prefab here.")]
    public GameObject butterflyPrefab;

    [Header("Emission Module")]
    [Tooltip("How many butterflies spawn per second.")]
    public float spawnRate = 3f;
    [Tooltip("Maximum number of butterflies alive at the same time.")]
    public int maxParticles = 25;

    [Header("Shape Module")]
    [Tooltip("The size of the box area where butterflies can appear.")]
    public Vector3 spawnBoxSize = new Vector3(5f, 2f, 5f);

    [Header("Main Module (Lifetime, Speed & Size)")]
    public Vector2 startLifetime = new Vector2(6f, 10f);
    public Vector2 startSpeed = new Vector2(1.5f, 3f);
    public Vector2 startScale = new Vector2(0.8f, 1.2f);
    [Tooltip("General direction the swarm flies toward.")]
    public Vector3 baseFlightDirection = new Vector3(0f, 0.3f, 1f);

    [Header("Noise / Flutter Module")]
    [Tooltip("How fast they bob up and down.")]
    public float bobFrequency = 3.5f;
    [Tooltip("How high/low they bob while flying.")]
    public float bobAmplitude = 0.6f;
    [Tooltip("How sharply they wander left, right, up, and down.")]
    public float wanderStrength = 2.0f;

    [Header("Animation Desync")]
    [Tooltip("Randomizes the Animator speed so their wings don't flap in sync.")]
    public Vector2 animSpeedRange = new Vector2(0.85f, 1.25f);

    private float spawnTimer;
    private List<GameObject> activeButterflies = new List<GameObject>();

    void Update()
    {
        // Clean up references to butterflies that have finished their lifetime
        activeButterflies.RemoveAll(item => item == null);

        // Spawn logic based on Emission settings
        if (butterflyPrefab != null && activeButterflies.Count < maxParticles)
        {
            spawnTimer += Time.deltaTime;
            if (spawnTimer >= 1f / spawnRate)
            {
                SpawnButterfly();
                spawnTimer = 0f;
            }
        }
    }

    void SpawnButterfly()
    {
        // 1. Calculate random spawn position inside the box
        Vector3 randomOffset = new Vector3(
            Random.Range(-spawnBoxSize.x * 0.5f, spawnBoxSize.x * 0.5f),
            Random.Range(-spawnBoxSize.y * 0.5f, spawnBoxSize.y * 0.5f),
            Random.Range(-spawnBoxSize.z * 0.5f, spawnBoxSize.z * 0.5f)
        );
        Vector3 spawnPos = transform.TransformPoint(randomOffset);

        // 2. Instantiate the butterfly
        GameObject b = Instantiate(butterflyPrefab, spawnPos, Quaternion.identity, transform);
        activeButterflies.Add(b);

        // 3. Apply random Start Scale
        float scale = Random.Range(startScale.x, startScale.y);
        b.transform.localScale = Vector3.one * scale;

        // 4. Offset and randomize wing flap animation so they don't look like clones
        Animator anim = b.GetComponentInChildren<Animator>();
        if (anim != null)
        {
            anim.speed = Random.Range(animSpeedRange.x, animSpeedRange.y);
            anim.Play(0, -1, Random.Range(0f, 1f)); // Starts flap cycle at a random frame
        }

        // Same for models imported with Legacy animation (an Animation component instead of an Animator)
        Animation legacy = b.GetComponentInChildren<Animation>();
        if (legacy != null && legacy.clip != null)
        {
            AnimationState flap = legacy[legacy.clip.name];
            flap.speed = Random.Range(animSpeedRange.x, animSpeedRange.y);
            flap.normalizedTime = Random.Range(0f, 1f);
        }

        // 5. Assign flight movement and lifetime
        float lifetime = Random.Range(startLifetime.x, startLifetime.y);
        float speed = Random.Range(startSpeed.x, startSpeed.y);

        ButterflyAgent agent = b.AddComponent<ButterflyAgent>();
        agent.Initialize(
            transform.TransformDirection(baseFlightDirection.normalized),
            speed,
            lifetime,
            bobFrequency,
            bobAmplitude,
            wanderStrength,
            scale
        );
    }

    // Draws the green spawn box in the Scene view when selected
    void OnDrawGizmosSelected()
    {
        Gizmos.color = new Color(0.2f, 1f, 0.4f, 0.5f);
        Gizmos.matrix = transform.localToWorldMatrix;
        Gizmos.DrawWireCube(Vector3.zero, spawnBoxSize);
    }
}

// Helper class automatically attached to each spawned butterfly to drive its flight
public class ButterflyAgent : MonoBehaviour
{
    private Vector3 currentDirection;
    private float speed;
    private float lifetime;
    private float age;
    private float bobFreq;
    private float bobAmp;
    private float wander;
    private float noiseSeed;
    private float maxScale;

    public void Initialize(Vector3 dir, float spd, float life, float bFreq, float bAmp, float wndr, float scl)
    {
        currentDirection = dir;
        speed = spd;
        lifetime = life;
        bobFreq = bFreq;
        bobAmp = bAmp;
        wander = wndr;
        maxScale = scl;
        noiseSeed = Random.Range(0f, 100f);

        if (currentDirection != Vector3.zero)
            transform.rotation = Quaternion.LookRotation(currentDirection);
    }

    void Update()
    {
        age += Time.deltaTime;
        if (age >= lifetime)
        {
            Destroy(gameObject);
            return;
        }

        // Smoothly scale in at birth and scale out before disappearing
        float lifePercent = age / lifetime;
        if (lifePercent < 0.1f)
            transform.localScale = Vector3.one * (maxScale * (lifePercent / 0.1f));
        else if (lifePercent > 0.85f)
            transform.localScale = Vector3.one * (maxScale * ((1f - lifePercent) / 0.15f));

        // Perlin noise for smooth, natural wandering
        float yawNoise = (Mathf.PerlinNoise(Time.time * 0.8f, noiseSeed) - 0.5f) * 2f;
        float pitchNoise = (Mathf.PerlinNoise(noiseSeed, Time.time * 0.8f) - 0.5f) * 2f;

        Quaternion wanderRot = Quaternion.Euler(
            pitchNoise * wander * 40f * Time.deltaTime,
            yawNoise * wander * 60f * Time.deltaTime,
            0f
        );
        currentDirection = (wanderRot * currentDirection).normalized;

        // Vertical sine wave for classic butterfly bobbing
        float verticalBob = Mathf.Sin((Time.time + noiseSeed) * bobFreq) * bobAmp;
        Vector3 finalVelocity = (currentDirection * speed) + (Vector3.up * verticalBob);

        // Move and smoothly rotate toward the flight path
        transform.position += finalVelocity * Time.deltaTime;
        if (finalVelocity != Vector3.zero)
        {
            Quaternion targetRot = Quaternion.LookRotation(finalVelocity.normalized);
            transform.rotation = Quaternion.Slerp(transform.rotation, targetRot, Time.deltaTime * 6f);
        }
    }
}
