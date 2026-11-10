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

    [Tooltip("Re-apply every frame (LateUpdate). Enable only if a Timeline/Animator keeps turning the meshes back on.")]
    public bool reapplyEveryFrame = false;

    [Header("Book texture")]
    [Tooltip("Book texture for Male. Materials using the other gender's texture are switched to this one.")]
    public Texture maleBookTexture;

    [Tooltip("Book texture for Female.")]
    public Texture femaleBookTexture;

    HashSet<string> maleSet, femaleSet;
    readonly List<GameObject> maleObjects = new List<GameObject>();
    readonly List<GameObject> femaleObjects = new List<GameObject>();
    bool male;

    void Awake()
    {
        maleSet = new HashSet<string>(maleMeshNames);
        femaleSet = new HashSet<string>(femaleMeshNames);
    }

    void Start()
    {
        Apply(GenderSelection.Current);
    }

    void LateUpdate()
    {
        // Runs after Timeline/Animator evaluation, so it wins any fight over the state.
        if (reapplyEveryFrame) SetStates();
    }

    public void Apply(GenderSelection.Gender gender)
    {
        male = gender == GenderSelection.Gender.Male;

        // Cache the matching GameObjects once (includes inactive prefabs).
        maleObjects.Clear();
        femaleObjects.Clear();
        foreach (Renderer r in GetAllRenderers())
        {
            if (maleSet.Contains(r.name)) maleObjects.Add(r.gameObject);
            else if (femaleSet.Contains(r.name)) femaleObjects.Add(r.gameObject);

            SwapBookTexture(r);
        }

        SetStates();
    }

    void SwapBookTexture(Renderer r)
    {
        if (maleBookTexture == null || femaleBookTexture == null) return;
        Texture wanted = male ? maleBookTexture : femaleBookTexture;
        Texture other = male ? femaleBookTexture : maleBookTexture;

        Material[] shared = r.sharedMaterials;
        for (int i = 0; i < shared.Length; i++)
        {
            if (shared[i] == null) continue;
            foreach (int id in shared[i].GetTexturePropertyNameIDs())
                if (shared[i].GetTexture(id) == other)
                    r.materials[i].SetTexture(id, wanted); // instance, so the .mat asset is never modified
        }
    }

    void SetStates()
    {
        // SetActive on the CHILD itself: its own active flag stays false even
        // when a parent is activated later, so the mesh remains hidden.
        for (int i = 0; i < maleObjects.Count; i++)
            if (maleObjects[i] != null && maleObjects[i].activeSelf != male)
                maleObjects[i].SetActive(male);

        for (int i = 0; i < femaleObjects.Count; i++)
            if (femaleObjects[i] != null && femaleObjects[i].activeSelf != !male)
                femaleObjects[i].SetActive(!male);
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