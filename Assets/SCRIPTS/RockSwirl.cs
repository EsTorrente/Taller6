using UnityEngine;
using UnityEngine.Playables;

// The rocks only fall straight into the black hole in the animation; this swings them around it too, the same way
// the disc turns. It runs after the Timeline has posed them each frame, so the turn never piles up.
public class RockSwirl : MonoBehaviour
{
    [Tooltip("BlackHole_VFX > Ring. The rocks turn around its centre, the way the disc spins")]
    public Transform disc;
    public Transform[] rocks;
    [Tooltip("Degrees per second around the black hole (negative turns the other way)")]
    public float speed = 3f;
    [Tooltip("The scene's timeline; its time is used so the swirl follows scrubbing and replays")]
    public PlayableDirector director;

    void LateUpdate()
    {
        if (!disc) return;
        float t = director ? (float)director.time : Time.timeSinceLevelLoad;
        var m = disc.localToWorldMatrix;
        // the disc spins around its own up; a mirrored parent would flip that
        var axis = m.MultiplyVector(Vector3.up).normalized * Mathf.Sign(m.determinant);
        var turn = Quaternion.AngleAxis(speed * t, axis);
        var center = disc.position;
        foreach (var rock in rocks)
        {
            if (!rock) continue;
            rock.SetPositionAndRotation(center + turn * (rock.position - center), turn * rock.rotation);
        }
    }
}
