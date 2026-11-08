using UnityEngine;

public static class LanguageSelection
{
    private const string Key = "SelectedLanguage";

    public enum Language { English, Spanish }

    // Static values survive scene loads. PlayerPrefs also keeps it between sessions.
    public static Language Current
    {
        get => (Language)PlayerPrefs.GetInt(Key, (int)Language.English);
        set
        {
            PlayerPrefs.SetInt(Key, (int)value);
            PlayerPrefs.Save();
        }
    }
}
