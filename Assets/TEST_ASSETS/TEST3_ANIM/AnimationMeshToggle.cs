
using UnityEngine;

public class AnimationMeshToggle : MonoBehaviour
{
    [SerializeField] private GameObject meshToDisable;

    public void DisableMesh()
    {
        if (meshToDisable != null)
        {
            meshToDisable.SetActive(false);
        }
    }
}