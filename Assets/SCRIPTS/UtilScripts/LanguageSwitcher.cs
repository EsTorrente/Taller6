using UnityEngine;

public class LanguageSwitcher : MonoBehaviour
{
    // Hook these up to the ENGLISH / SPANISH buttons' OnClick
    public void SelectEnglish() => LanguageSelection.Current = LanguageSelection.Language.English;
    public void SelectSpanish() => LanguageSelection.Current = LanguageSelection.Language.Spanish;
}
