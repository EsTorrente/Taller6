using System.Linq;
using UnityEngine;
using UnityEngine.Playables;
using UnityEngine.Timeline;

public class CinematicVoiceApplier : MonoBehaviour
{
    [System.Serializable]
    public class VoiceLine
    {
        public AudioClip maleEnglish;
        public AudioClip femaleEnglish;
        public AudioClip maleSpanish;
        public AudioClip femaleSpanish;

        public AudioClip Get(GenderSelection.Gender gender, LanguageSelection.Language language)
        {
            bool male = gender == GenderSelection.Gender.Male;
            if (language == LanguageSelection.Language.English)
                return male ? maleEnglish : femaleEnglish;
            return male ? maleSpanish : femaleSpanish;
        }
    }

    [Header("Timeline")]
    [Tooltip("The PlayableDirector that plays your cinematic.")]
    public PlayableDirector director;

    [Tooltip("Exact name of the Audio Track (as shown in the Timeline window) whose clips will be swapped.")]
    public string audioTrackName = "Voice";

    [Header("Voice lines")]
    [Tooltip("Element 0 replaces the audio of the FIRST clip on that track (ordered by start time), " +
             "element 1 the second clip, and so on. If the track has a single clip, use a single element.")]
    public VoiceLine[] voiceLines;

    [Header("Playback")]
    [Tooltip("Turn OFF 'Play On Awake' on the director and enable this, so the voice is swapped BEFORE the cinematic starts.")]
    public bool playDirectorAfterApply = true;

    void Start()
    {
        Apply(GenderSelection.Current, LanguageSelection.Current);

        if (playDirectorAfterApply && director != null)
            director.Play();
    }

    public void Apply(GenderSelection.Gender gender, LanguageSelection.Language language)
    {
        if (director == null)
        {
            Debug.LogWarning("CinematicVoiceApplier: no PlayableDirector assigned.", this);
            return;
        }

        var timeline = director.playableAsset as TimelineAsset;
        if (timeline == null)
        {
            Debug.LogWarning("CinematicVoiceApplier: the director has no Timeline asset.", this);
            return;
        }

        bool trackFound = false;

        foreach (TrackAsset track in timeline.GetOutputTracks())
        {
            if (!(track is AudioTrack) || track.name != audioTrackName) continue;
            trackFound = true;

            int i = 0;
            foreach (TimelineClip tc in track.GetClips().OrderBy(c => c.start))
            {
                if (i >= voiceLines.Length) break;

                var audioAsset = tc.asset as AudioPlayableAsset;
                AudioClip chosen = voiceLines[i].Get(gender, language);

                if (audioAsset != null && chosen != null)
                    audioAsset.clip = chosen;

                i++;
            }
        }

        if (!trackFound)
            Debug.LogWarning($"CinematicVoiceApplier: no Audio Track named '{audioTrackName}' found.", this);

        // If the graph was already built (e.g. Play On Awake), rebuild it so the new clips are used.
        if (director.playableGraph.IsValid())
            director.RebuildGraph();
    }
}
