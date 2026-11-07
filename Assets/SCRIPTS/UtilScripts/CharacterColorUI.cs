using UnityEngine;
using UnityEngine.SceneManagement;

public class CharacterColorUI : MonoBehaviour
{
    // =========================================================
    // COLOR VALUES
    // =========================================================

    // Hair
    private Color HairBlond =>
        HexToColor("FFFFE9");

    private Color HairBrown =>
        HexToColor("B39A7E");

    private Color HairBlack =>
        HexToColor("000000");

    private Color HairRed =>
        HexToColor("F38C3A");


    // Skin
    private Color SkinPale =>
        HexToColor("FFFCED");

    private Color SkinTan =>
        HexToColor("E3BC8A");

    private Color SkinBlack =>
        HexToColor("956931");


    // Eyes
    private Color EyeBlue =>
        HexToColor("FFFFFF");

    private Color EyeGreen =>
        HexToColor("D2E01D");

    private Color EyeBrown =>
        HexToColor("AB2C00");


    // =========================================================
    // HAIR BUTTONS
    // =========================================================

    public void SelectHairBlond()
    {
        CharacterColorManager.Instance.SetHairColor(
            HairBlond
        );
    }


    public void SelectHairBrown()
    {
        CharacterColorManager.Instance.SetHairColor(
            HairBrown
        );
    }


    public void SelectHairBlack()
    {
        CharacterColorManager.Instance.SetHairColor(
            HairBlack
        );
    }


    public void SelectHairRed()
    {
        CharacterColorManager.Instance.SetHairColor(
            HairRed
        );
    }


    // =========================================================
    // SKIN BUTTONS
    // =========================================================

    public void SelectSkinPale()
    {
        CharacterColorManager.Instance.SetSkinColor(
            SkinPale
        );
    }


    public void SelectSkinTan()
    {
        CharacterColorManager.Instance.SetSkinColor(
            SkinTan
        );
    }


    public void SelectSkinBlack()
    {
        CharacterColorManager.Instance.SetSkinColor(
            SkinBlack
        );
    }


    // =========================================================
    // EYE BUTTONS
    // =========================================================

    public void SelectEyeBlue()
    {
        CharacterColorManager.Instance.SetEyeColor(
            EyeBlue
        );
    }


    public void SelectEyeGreen()
    {
        CharacterColorManager.Instance.SetEyeColor(
            EyeGreen
        );
    }


    public void SelectEyeBrown()
    {
        CharacterColorManager.Instance.SetEyeColor(
            EyeBrown
        );
    }


    // =========================================================
    // CONTINUE
    // =========================================================

    public void Continue()
    {
        SceneManager.LoadScene("Cinematic");
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