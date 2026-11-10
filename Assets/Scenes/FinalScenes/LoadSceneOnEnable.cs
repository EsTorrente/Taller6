
using UnityEngine;
using UnityEngine.SceneManagement;

public class LoadSceneOnEnable : MonoBehaviour
{
    [Header("Scene Settings")]
    [SerializeField] private string sceneToLoad;

    private void OnEnable()
    {
        if (string.IsNullOrEmpty(sceneToLoad))
        {
            Debug.LogWarning("No scene assigned!", this);
            return;
        }

        SceneManager.LoadScene(sceneToLoad);
    }
}
