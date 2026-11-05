using UnityEngine;

public static class GenderSelection
{
    private const string Key = "SelectedGender";

    public enum Gender { Male, Female }

    // Static values survive scene loads. PlayerPrefs also keeps it between sessions.
    public static Gender Current
    {
        get => (Gender)PlayerPrefs.GetInt(Key, (int)Gender.Male);
        set
        {
            PlayerPrefs.SetInt(Key, (int)value);
            PlayerPrefs.Save();
        }
    }
}