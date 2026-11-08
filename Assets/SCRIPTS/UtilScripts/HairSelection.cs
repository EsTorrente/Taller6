using UnityEngine;

public static class HairSelection
{
    private const string Key = "SelectedHair";

    // Index of the selected hair (0 = first name in the applier's list, 1 = second, ...).
    // Static values survive scene loads. PlayerPrefs also keeps it between sessions.
    public static int Current
    {
        get => PlayerPrefs.GetInt(Key, 0);
        set
        {
            PlayerPrefs.SetInt(Key, value);
            PlayerPrefs.Save();
        }
    }
}
