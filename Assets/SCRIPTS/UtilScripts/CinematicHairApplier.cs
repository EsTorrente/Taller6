using System.Collections.Generic;
using UnityEngine;

public class CinematicHairApplier : MonoBehaviour
{
    [Header("Hair mesh object names (same in every prefab)")]
    [Tooltip("One name per hair option. The ORDER matters: element 0 = hair 0, element 1 = hair 1, etc. " +
             "This must match the index your hair buttons send.")]
    public string[] hairMeshNames;

    [Header("Optional")]
    [Tooltip("Limit the search to these prefab roots. Leave empty to search the whole scene.")]
    public Transform[] prefabRoots;

    [Tooltip("Re-apply every frame (LateUpdate). Enable only if a Timeline/Animator keeps turning the meshes back on.")]
    public bool reapplyEveryFrame = false;

    // hairObjects[i] = every GameObject (one per prefab) that belongs to hair option i
    List<GameObject>[] hairObjects;
    int selected;

    void Start()
    {
        Apply(HairSelection.Current);
    }

    void LateUpdate()
    {
        // Runs after Timeline/Animator evaluation, so it wins any fight over the state.
        if (reapplyEveryFrame && hairObjects != null) SetStates();
    }

    public void Apply(int hairIndex)
    {
        selected = hairIndex;

        // Map each name to its option index.
        var indexByName = new Dictionary<string, int>();
        for (int i = 0; i < hairMeshNames.Length; i++)
            indexByName[hairMeshNames[i]] = i;

        hairObjects = new List<GameObject>[hairMeshNames.Length];
        for (int i = 0; i < hairObjects.Length; i++)
            hairObjects[i] = new List<GameObject>();

        // Cache the matching GameObjects once (includes inactive prefabs).
        foreach (Renderer r in GetAllRenderers())
            if (indexByName.TryGetValue(r.name, out int idx))
                hairObjects[idx].Add(r.gameObject);

        SetStates();
    }

    void SetStates()
    {
        // SetActive on the CHILD itself: its own active flag stays false even
        // when a parent is activated later, so the mesh remains hidden.
        for (int i = 0; i < hairObjects.Length; i++)
        {
            bool shouldBeOn = i == selected;
            foreach (GameObject go in hairObjects[i])
                if (go != null && go.activeSelf != shouldBeOn)
                    go.SetActive(shouldBeOn);
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
            foreach (Renderer r in FindObjectsByType<Renderer>(
                         FindObjectsInactive.Include, FindObjectsSortMode.None))
                yield return r;
        }
    }
}
