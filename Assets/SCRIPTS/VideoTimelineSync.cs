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
        [System.NonSerialized] public float nextCheck;   // next time (unscaled) this video needs looking at
        [System.NonSerialized] public bool active;       // last frame: should be playing and was prepared
    }

    public PlayableDirector director;
    public Entry[] videos;
    [Tooltip("How far a video may drift from the Timeline before it is corrected (seconds)")]
    public float maxDrift = 0.15f;
    [Tooltip("Start the Timeline anyway after this long if a video isn't ready (seconds)")]
    public float prepareTimeout = 5f;
    [Tooltip("Optional. When set, this Timeline starts in step with the Master one instead of from 0 (e.g. a scene section inside the Cinematic)")]
    public PlayableDirector master;
    [Tooltip("Master time at which this Timeline's time 0 falls (seconds)")]
    public double masterOffset;

    // Drift is checked 10x per second instead of every frame (the tolerance is 0.15 s, so this is plenty).
    const float CheckInterval = 0.1f;
    // A seek takes a moment to land, so give it half a second before checking again.
    const float SeekCooldown = 0.5f;

    bool started;
    float waited;

    void Start()
    {
        // show the first frame of the Timeline while the videos get ready
        director.playOnAwake = false;
        if (director.state == PlayState.Playing) director.Pause();
        director.time = 0;
        director.Evaluate();

        for (int i = 0; i < videos.Length; i++)
        {
            VideoPlayer p = videos[i].player;
            if (!p) continue;
            p.playOnAwake = false;
            p.Prepare();
            if (p.targetTexture) ClearToBlack(p.targetTexture);
        }
    }

    void Update()
    {
        if (!started)
        {
            waited += Time.unscaledDeltaTime;
            bool ready = true;
            for (int i = 0; i < videos.Length; i++)
            {
                VideoPlayer p = videos[i].player;
                if (p) ready &= p.isPrepared;
            }
            if (!ready && waited < prepareTimeout) return;
            started = true;
            // also covers the time spent waiting for the videos, so the section doesn't fall behind the master's music
            if (master) director.time = System.Math.Max(0, master.time - masterOffset);
            director.Play();
        }

        bool running = director.state == PlayState.Playing;
        double now = director.time;
        float t = Time.unscaledTime;

        for (int i = 0; i < videos.Length; i++)
        {
            Entry e = videos[i];
            VideoPlayer p = e.player;
            if (!p) continue;

            bool shown = !e.showWhile || e.showWhile.activeInHierarchy;
            if (!shown) e.start = -1;
            else if (e.start < 0) e.start = e.showWhile ? now : 0;

            bool wants = shown && running;

            // Fast path: video is playing fine and nothing is due yet, so skip all VideoPlayer calls.
            if (wants && e.active && t < e.nextCheck) continue;

            bool canPlay = wants && p.isPrepared;

            if (!canPlay)
            {
                if (e.active)
                {
                    // just stopped being active: pause right away
                    e.active = false;
                    if (p.isPlaying) p.Pause();
                    e.nextCheck = t + CheckInterval;
                }
                else if (t >= e.nextCheck)
                {
                    // slow safety net so a paused video can't keep running by accident
                    e.nextCheck = t + CheckInterval;
                    if (p.isPlaying) p.Pause();
                }
                continue;
            }

            if (!e.active)
            {
                // just became active: check immediately so a resumed video is brought in step at once
                e.active = true;
            }

            e.nextCheck = t + CheckInterval;

            // where the video should be: Timeline time since it started, at the player's speed
            double target = (now - e.start) * p.playbackSpeed;
            double length = p.length;
            if (length > 0 && target >= length)
            {
                if (!p.isLooping)
                {
                    if (p.isPlaying) p.Pause();
                    continue;
                }
                target %= length;
            }

            if (!p.isPlaying) p.Play();

            if (System.Math.Abs(p.time - target) > maxDrift && p.canSetTime)
            {
                p.time = target;
                e.nextCheck = t + SeekCooldown;
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