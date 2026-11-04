using UnityEngine;

public class GenderSwitcher : MonoBehaviour
{
    // These lists hold the mesh RENDERERS (MeshRenderer / SkinnedMeshRenderer), not GameObjects.
    // Turning a renderer on or off hides the mesh without deactivating anything in the FBX prefab,
    // so bones, animators and the rest of the hierarchy keep working.
    // Tip: you can drag a mesh GameObject from the hierarchy straight into a slot;
    // Unity picks its renderer automatically.

    [Header("ASTRONAUT")]
    [Tooltip("Mesh renderers that should be ON when Astronaut Male is selected.")]
    public Renderer[] astronautMaleMeshes;

    [Tooltip("Mesh renderers that should be ON when Astronaut Female is selected.")]
    public Renderer[] astronautFemaleMeshes;


    [Header("KID")]
    [Tooltip("Mesh renderers that should be ON when Kid Male is selected.")]
    public Renderer[] kidMaleMeshes;

    [Tooltip("Mesh renderers that should be ON when Kid Female is selected.")]
    public Renderer[] kidFemaleMeshes;


    // Called by the MALE button
    public void SelectMale()
    {
        SetMeshesVisible(astronautMaleMeshes, true);
        SetMeshesVisible(astronautFemaleMeshes, false);

        SetMeshesVisible(kidMaleMeshes, true);
        SetMeshesVisible(kidFemaleMeshes, false);
    }


    // Called by the FEMALE button
    public void SelectFemale()
    {
        SetMeshesVisible(astronautMaleMeshes, false);
        SetMeshesVisible(astronautFemaleMeshes, true);

        SetMeshesVisible(kidMaleMeshes, false);
        SetMeshesVisible(kidFemaleMeshes, true);
    }


    private void SetMeshesVisible(Renderer[] meshes, bool visible)
    {
        if (meshes == null)
            return;

        foreach (Renderer mesh in meshes)
        {
            if (mesh != null)
            {
                // A disabled renderer is neither drawn nor casts shadows.
                mesh.enabled = visible;
            }
        }
    }
}