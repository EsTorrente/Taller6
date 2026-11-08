using UnityEngine;

public class HairSwitcher : MonoBehaviour
{
    // Hook this to each hair button's OnClick and type the hair number in the
    // int field (0 = first hair, 1 = second, ...).
    public void SelectHair(int index) => HairSelection.Current = index;

    // Optional: handy for "next / previous" arrows. Set hairCount in the Inspector.
    public int hairCount = 1;
    public void NextHair() => HairSelection.Current = (HairSelection.Current + 1) % hairCount;
    public void PreviousHair() => HairSelection.Current = (HairSelection.Current - 1 + hairCount) % hairCount;
}
