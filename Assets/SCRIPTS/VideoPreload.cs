using UnityEngine;
using UnityEngine.Video;

// Opens the video ahead of time (switch this object on a few seconds before its section)
// so it can start right away instead of loading when the section begins.
[RequireComponent(typeof(VideoPlayer))]
public class VideoPreload : MonoBehaviour
{
    void OnEnable() => GetComponent<VideoPlayer>().Prepare();
}
