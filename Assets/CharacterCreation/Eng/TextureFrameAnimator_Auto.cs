using UnityEngine;

[ExecuteAlways]
[RequireComponent(typeof(Renderer))]
public class TextureFrameAnimator_Auto : MonoBehaviour
{
    [Header("Animation")]
    public Texture[] frames;

    [Min(0f)]
    public float framesPerSecond = 1f;

    public bool playAutomatically = true;
    public bool Loop = true;

    [Tooltip("The frame to start from.")]
    [Min(0)]
    public int startFrame = 0;

    [Header("Material")]
    [SerializeField]
    private string textureProperty = "_BaseMap";

    private Renderer meshRenderer;
    private MaterialPropertyBlock propertyBlock;
    private int propertyID;

    private float frameTimer;
    private int currentFrame;
    private bool wasPlaying;

    private void OnEnable()
    {
        CacheComponents();
        currentFrame = GetStartingFrame();
        frameTimer = 0f;
        wasPlaying = playAutomatically;
        ApplyFrame();
    }

    private void Update()
    {
        CacheComponents();

        if (frames == null || frames.Length == 0)
            return;

        // In Edit Mode, show the selected starting frame without running
        // an animation clock. The animation plays when the game runs.
        if (!Application.isPlaying)
        {
            ApplyFrame();
            return;
        }

        if (!playAutomatically || framesPerSecond <= 0f)
        {
            ApplyFrame();
            return;
        }

        frameTimer += Time.deltaTime;
        float frameDuration = 1f / framesPerSecond;

        while (frameTimer >= frameDuration)
        {
            frameTimer -= frameDuration;
            AdvanceFrame();
        }

        ApplyFrame();
    }

    private void OnValidate()
    {
        CacheComponents();

        if (framesPerSecond < 0f)
            framesPerSecond = 0f;

        currentFrame = GetStartingFrame();
        ApplyFrame();
    }

    private void CacheComponents()
    {
        if (meshRenderer == null)
            meshRenderer = GetComponent<Renderer>();

        if (propertyBlock == null)
            propertyBlock = new MaterialPropertyBlock();

        propertyID = Shader.PropertyToID(textureProperty);
    }

    private int GetStartingFrame()
    {
        if (frames == null || frames.Length == 0)
            return 0;

        return Mathf.Clamp(startFrame, 0, frames.Length - 1);
    }

    private void AdvanceFrame()
    {
        if (frames == null || frames.Length == 0)
            return;

        currentFrame++;

        if (currentFrame >= frames.Length)
        {
            if (Loop)
                currentFrame = 0;
            else
            {
                currentFrame = frames.Length - 1;
                playAutomatically = false;
            }
        }
    }

    private void ApplyFrame()
    {
        if (meshRenderer == null || frames == null || frames.Length == 0)
            return;

        currentFrame = Mathf.Clamp(currentFrame, 0, frames.Length - 1);

        if (frames[currentFrame] == null)
            return;

        if (propertyBlock == null)
            propertyBlock = new MaterialPropertyBlock();

        meshRenderer.GetPropertyBlock(propertyBlock);
        propertyBlock.SetTexture(propertyID, frames[currentFrame]);
        meshRenderer.SetPropertyBlock(propertyBlock);
    }

    // Optional: call this from another script to restart the animation.
    public void RestartAnimation()
    {
        currentFrame = GetStartingFrame();
        frameTimer = 0f;
        playAutomatically = true;
        ApplyFrame();
    }

    // Optional: call this to pause or resume playback.
    public void SetPlaying(bool isPlaying)
    {
        playAutomatically = isPlaying;
    }
}
