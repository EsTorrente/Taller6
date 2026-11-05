using System.Collections.Generic;
using UnityEngine;

public class CinematicGenderApplier : MonoBehaviour
{
    [Header("Mesh object names (same in every prefab)")]
    [Tooltip("Names of mesh GameObjects that should be ON for Male.")]
    public string[] maleMeshNames;

    [Tooltip("Names of mesh GameObjects that should be ON for Female.")]
    public string[] femaleMeshNames;

    [Header("Optional")]
    [Tooltip("Limit the search to these prefab roots. Leave empty to search the whole scene.")]
    public Transform[] prefabRoots;

    void Start()
    {
        Apply(GenderSelection.Current);
    }

    public void Apply(GenderSelection.Gender gender)
    {
        bool male = gender == GenderSelection.Gender.Male;

        var maleSet = new HashSet<string>(maleMeshNames);
        var femaleSet = new HashSet<string>(femaleMeshNames);

        foreach (Renderer r in GetAllRenderers())
        {
            if (maleSet.Contains(r.name))
                r.enabled = male;
            else if (femaleSet.Contains(r.name))
                r.enabled = !male;
        }
    }

    IEnumerable<Renderer> GetAllRenderers()
    {
        if (prefabRoots != null && prefabRoots.Length > 0)
        {
            foreach (Transform root in prefabRoots)
                if (root != null)
                    foreach (Renderer r in root.GetComponentsInChildren<Renderer>(true))
                        yield return r;
        }
        else
        {
            // Unity 6 API (FindObjectsOfType is deprecated)
            foreach (Renderer r in FindObjectsByType<Renderer>(
                         FindObjectsInactive.Include, FindObjectsSortMode.None))
                yield return r;
        }
    }
}