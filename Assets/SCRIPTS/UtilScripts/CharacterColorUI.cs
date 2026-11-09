using System.Collections;
using UnityEngine;
using UnityEngine.SceneManagement;

public class CharacterColorUI : MonoBehaviour
{
    // =========================================================
    // COLOR VALUES
    // =========================================================

    // Hair
    private Color HairBlond => HexToColor("FFFFE9");
    private Color HairBrown => HexToColor("B39A7E");
    private Color HairBlack => HexToColor("000000");
    private Color HairRed => HexToColor("F38C3A");

    // Skin
    private Color SkinPale => HexToColor("FFFCED");
    private Color SkinTan => HexToColor("E3BC8A");
    private Color SkinBlack => HexToColor("956931");

    // Eyes
    private Color EyeBlue => HexToColor("FFFFFF");
    private Color EyeGreen => HexToColor("D2E01D");
    private Color EyeBrown => HexToColor("AB2C00");


    // =========================================================
    // SCENE TRANSITION
    // =========================================================

    [Header("Scene Transition")]
    [SerializeField] private string nextSceneName = "Cinematic";

    [Tooltip("How long to wait before loading the next scene. The music fades during this time.")]
    [SerializeField] private float transitionDuration = 4f;

    [Tooltip("Assign the AudioSource that plays your background music.")]
    [SerializeField] private AudioSource backgroundMusic;

    private bool isTransitioning = false;


    // =========================================================
    // HAIR BUTTONS
    // =========================================================

    public void SelectHairBlond()
    {
        CharacterColorManager.Instance.SetHairColor(HairBlond);
    }

    public void SelectHairBrown()
    {
        CharacterColorManager.Instance.SetHairColor(HairBrown);
    }

    public void SelectHairBlack()
    {
        CharacterColorManager.Instance.SetHairColor(HairBlack);
    }

    public void SelectHairRed()
    {
        CharacterColorManager.Instance.SetHairColor(HairRed);
    }


    // =========================================================
    // SKIN BUTTONS
    // =========================================================

    public void SelectSkinPale()
    {
        CharacterColorManager.Instance.SetSkinColor(SkinPale);
    }

    public void SelectSkinTan()
    {
        CharacterColorManager.Instance.SetSkinColor(SkinTan);
    }

    public void SelectSkinBlack()
    {
        CharacterColorManager.Instance.SetSkinColor(SkinBlack);
    }


    // =========================================================
    // EYE BUTTONS
    // =========================================================

    public void SelectEyeBlue()
    {
        CharacterColorManager.Instance.SetEyeColor(EyeBlue);
    }

    public void SelectEyeGreen()
    {
        CharacterColorManager.Instance.SetEyeColor(EyeGreen);
    }

    public void SelectEyeBrown()
    {
        CharacterColorManager.Instance.SetEyeColor(EyeBrown);
    }


    // =========================================================
    // CONTINUE
    // =========================================================

    public void Continue()
    {
        // Prevents the transition from starting multiple times
        // if the player presses the button repeatedly.
        if (isTransitioning)
            return;

        StartCoroutine(TransitionToNextScene());
    }

    private IEnumerator TransitionToNextScene()
    {
        isTransitioning = true;

        float duration = Mathf.Max(0f, transitionDuration);

        // Fade the background music from its current volume to zero.
        if (backgroundMusic != null && backgroundMusic.isPlaying && duration > 0f)
        {
            float startingVolume = backgroundMusic.volume;
            float elapsedTime = 0f;

            while (elapsedTime < duration)
            {
                elapsedTime += Time.unscaledDeltaTime;

                float fadeProgress = Mathf.Clamp01(elapsedTime / duration);
                backgroundMusic.volume = Mathf.Lerp(
                    startingVolume,
                    0f,
                    fadeProgress
                );

                yield return null;
            }

            backgroundMusic.volume = 0f;
        }
        else if (duration > 0f)
        {
            // Still wait for the transition duration if no music is assigned.
            yield return new WaitForSecondsRealtime(duration);
        }

        SceneManager.LoadScene(nextSceneName);
    }


    // =========================================================
    // HEX CONVERTER
    // =========================================================

    private static Color HexToColor(string hex)
    {
        Color color;

        ColorUtility.TryParseHtmlString(
            "#" + hex,
            out color
        );

        return color;
    }
}
