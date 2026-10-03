using UnityEngine;

public class GenderSwitcher : MonoBehaviour
{
    [Header("ASTRONAUT")]
    [Tooltip("Meshes that should be ON when Astronaut Male is selected.")]
    public GameObject[] astronautMaleMeshes;

    [Tooltip("Meshes that should be ON when Astronaut Female is selected.")]
    public GameObject[] astronautFemaleMeshes;


    [Header("KID")]
    [Tooltip("Meshes that should be ON when Kid Male is selected.")]
    public GameObject[] kidMaleMeshes;

    [Tooltip("Meshes that should be ON when Kid Female is selected.")]
    public GameObject[] kidFemaleMeshes;


    // Called by the MALE button
    public void SelectMale()
    {
        SetMeshesActive(astronautMaleMeshes, true);
        SetMeshesActive(astronautFemaleMeshes, false);

        SetMeshesActive(kidMaleMeshes, true);
        SetMeshesActive(kidFemaleMeshes, false);
    }


    // Called by the FEMALE button
    public void SelectFemale()
    {
        SetMeshesActive(astronautMaleMeshes, false);
        SetMeshesActive(astronautFemaleMeshes, true);

        SetMeshesActive(kidMaleMeshes, false);
        SetMeshesActive(kidFemaleMeshes, true);
    }


    private void SetMeshesActive(GameObject[] meshes, bool active)
    {
        if (meshes == null)
            return;

        foreach (GameObject mesh in meshes)
        {
            if (mesh != null)
            {
                mesh.SetActive(active);
            }
        }
    }
}