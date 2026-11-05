
using UnityEngine;
using PixeLadder.EasyTransition;
using PixeLadder.EasyTransition.Effects;

public class TimelineFadeTrigger : MonoBehaviour
{
    [SerializeField] private FadeEffect fadeEffect;

    public void PlayFade()
    {
        if (fadeEffect == null)
        {
            Debug.LogError("FadeEffect is not assigned!");
            return;
        }

        if (SceneTransitioner.Instance == null)
        {
            Debug.LogError("SceneTransitioner was not found!");
            return;
        }

        SceneTransitioner.Instance.PlayTransition(
            () => { },
            fadeEffect
        );
    }
}
