
using UnityEngine;

[ExecuteAlways]
public class TextureFrameAnimator : MonoBehaviour
{
    public Texture[] frames;

    public float Frame = 0;
    public bool Loop = true;

    [SerializeField]
    private string textureProperty = "_BaseMap";

    private Renderer meshRenderer;
    private MaterialPropertyBlock propertyBlock;
    private int propertyID;

    private void OnEnable()
    {
        meshRenderer = GetComponent<Renderer>();
        propertyBlock = new MaterialPropertyBlock();
        propertyID = Shader.PropertyToID(textureProperty);
        ApplyFrame();
    }

    private void Update()
    {
        ApplyFrame();
    }

    public void OnDidApplyAnimationProperties()
    {
        ApplyFrame();
    }

    private void OnValidate()
    {
        if (meshRenderer == null)
            meshRenderer = GetComponent<Renderer>();

        propertyID = Shader.PropertyToID(textureProperty);
        ApplyFrame();
    }

    private void ApplyFrame()
    {
        if (meshRenderer == null)
            meshRenderer = GetComponent<Renderer>();

        if (meshRenderer == null || frames == null ||
            frames.Length == 0)
            return;

        if (propertyBlock == null)
            propertyBlock = new MaterialPropertyBlock();

        int index;

        if (Loop)
        {
            index = Mathf.FloorToInt(Frame) % frames.Length;
        }
        else
        {
            index = Mathf.Clamp(
                Mathf.FloorToInt(Frame),
                0,
                frames.Length - 1
            );
        }

        if (frames[index] == null)
            return;

        meshRenderer.GetPropertyBlock(propertyBlock);
        propertyBlock.SetTexture(propertyID, frames[index]);
        meshRenderer.SetPropertyBlock(propertyBlock);
    }
}
