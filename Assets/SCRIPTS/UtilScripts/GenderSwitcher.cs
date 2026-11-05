using UnityEngine;

public class GenderSwitcher : MonoBehaviour
{
    // Hook these up to the MALE / FEMALE buttons' OnClick
    public void SelectMale() => GenderSelection.Current = GenderSelection.Gender.Male;
    public void SelectFemale() => GenderSelection.Current = GenderSelection.Gender.Female;
}