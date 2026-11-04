using UnityEngine;
using UnityEngine.Playables;
using UnityEngine.Video;

// Keeps video players in step with the Timeline (and so with its audio).
// The Timeline waits until every video is ready, then they all start together; afterwards each video is nudged
// back whenever it drifts more than Max Drift from where the Timeline says it should be.
// A video with "Show While" plays from its start each time that object is switched on, and pauses while it is off.
public class VideoTimelineSync : MonoBehaviour
{
    [System.Serializable]
    public class Entry
    {
        public VideoPlayer player;
        [Tooltip("Empty = plays from the start of the Timeline. Otherwise the video starts when this object is switched on")]
        public GameObject showWhile;
        [System.NonSerialized] public double start = -1;
        [System.NonSerialized] public float seekedAt = -10;
    }

    public PlayableDirector director;
    public Entry[] videos;
    [Tooltip("How far a video may drift from the Timeline before it is corrected (seconds)")]
    public float maxDrift = 0.15f;
    [Tooltip("Start the Timeline anyway after this long if a video isn't ready (seconds)")]
    public float prepareTimeout = 5f;

    bool started;
    float waited;

    void Start()
    {
        // show the first frame of the Timeline while the videos get ready
        director.playOnAwake = false;
        if (director.state == PlayState.Playing) director.Pause();
        director.time = 0;
        director.Evaluate();
        foreach (var v in videos)
        {
            v.player.playOnAwake = false;
            v.player.Prepare();
            if (v.player.targetTexture) ClearToBlack(v.player.targetTexture);
        }
    }

    void Update()
    {
        if (!started)
        {
            waited += Time.unscaledDeltaTime;
            bool ready = true;
            foreach (var v in videos) ready &= v.player.isPrepared;
            if (!ready && waited < prepareTimeout) return;
            started = true;
            director.Play();
        }

        bool running = director.state == PlayState.Playing;
        double now = director.time;
        foreach (var v in videos)
        {
            VideoPlayer p = v.player;
            bool shown = !v.showWhile || v.showWhile.activeInHierarchy;
            if (!shown) v.start = -1;
            else if (v.start < 0) v.start = v.showWhile ? now : 0;

            if (!shown || !running || !p.isPrepared)
            {
                if (p.isPlaying) p.Pause();
                continue;
            }

            // where the video should be: Timeline time since it started, at the player's speed
            double target = (now - v.start) * p.playbackSpeed;
            if (p.length > 0 && target >= p.length)
            {
                if (!p.isLooping) { if (p.isPlaying) p.Pause(); continue; }
                target %= p.length;
            }
            if (!p.isPlaying) p.Play();
            // a seek takes a moment to land, so give it half a second before checking again
            if (Time.unscaledTime - v.seekedAt > 0.5f && System.Math.Abs(p.time - target) > maxDrift)
            {
                p.time = target;
                v.seekedAt = Time.unscaledTime;
            }
        }
    }

    static void ClearToBlack(RenderTexture rt)
    {
        var previous = RenderTexture.active;
        RenderTexture.active = rt;
        GL.Clear(false, true, Color.black);
        RenderTexture.active = previous;
    }
}
