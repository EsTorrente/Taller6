
using System.Collections;
using UnityEngine;

public class FadeSphere : MonoBehaviour
{
    public enum FadeColor
    {
        Black,
        White
    }

    [Header("References")]
    [SerializeField] private Renderer sphereRenderer;

    [Header("Fade Settings")]
    [SerializeField] private FadeColor fadeColor = FadeColor.Black;
    [SerializeField] private float fadeDuration = 1f;

    [Header("Startup")]
    [SerializeField] private bool startTransparent = true;

    private Material fadeMaterial;
    private Coroutine fadeCoroutine;

    private static readonly int BaseColorID =
        Shader.PropertyToID("_BaseColor");

    private static readonly int ColorID =
        Shader.PropertyToID("_Color");

    private Color targetColor;

    private void Awake()
    {
        if (sphereRenderer == null)
            sphereRenderer = GetComponent<Renderer>();

        // Create a material instance so we don't modify the asset.
        fadeMaterial = sphereRenderer.material;

        // Choose black or white.
        targetColor = fadeColor == FadeColor.Black
            ? Color.black
            : Color.white;

        targetColor.a = startTransparent ? 0f : 1f;

        SetAlpha(targetColor.a);
    }

    // Called by Timeline: fade from transparent to opaque.
    public void FadeIn()
    {
        StartFade(1f);
    }

    // Called by Timeline: fade from opaque to transparent.
    public void FadeOut()
    {
        StartFade(0f);
    }

    // Optional: immediately hide the sphere.
    public void HideImmediately()
    {
        StartFade(0f, true);
    }

    // Optional: immediately show the sphere.
    public void ShowImmediately()
    {
        StartFade(1f, true);
    }

    private void StartFade(float targetAlpha, bool instant = false)
    {
        if (fadeCoroutine != null)
            StopCoroutine(fadeCoroutine);

        if (instant)
        {
            SetAlpha(targetAlpha);
            return;
        }

        fadeCoroutine = StartCoroutine(
            FadeRoutine(targetAlpha)
        );
    }

    private IEnumerator FadeRoutine(float targetAlpha)
    {
        float startAlpha = targetColor.a;
        float elapsed = 0f;

        while (elapsed < fadeDuration)
        {
            elapsed += Time.deltaTime;

            float t = fadeDuration <= 0f
                ? 1f
                : Mathf.Clamp01(elapsed / fadeDuration);

            // Smooth transition.
            t = Mathf.SmoothStep(0f, 1f, t);

            float alpha = Mathf.Lerp(
                startAlpha,
                targetAlpha,
                t
            );

            SetAlpha(alpha);

            yield return null;
        }

        SetAlpha(targetAlpha);
        fadeCoroutine = null;
    }

    private void SetAlpha(float alpha)
    {
        targetColor.a = alpha;

        if (fadeMaterial.HasProperty(BaseColorID))
        {
            fadeMaterial.SetColor(BaseColorID, targetColor);
        }
        else if (fadeMaterial.HasProperty(ColorID))
        {
            fadeMaterial.SetColor(ColorID, targetColor);
        }
        else
        {
            Debug.LogError(
                "FadeSphere: Shader has no _BaseColor or _Color property."
            );
        }
    }

    private void OnDestroy()
    {
        if (fadeMaterial != null)
            Destroy(fadeMaterial);
    }
}
