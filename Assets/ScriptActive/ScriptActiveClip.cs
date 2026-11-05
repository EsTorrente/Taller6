using System;
using UnityEngine;
using UnityEngine.Playables;
using UnityEngine.Timeline;

[Serializable]
public class ScriptActiveClip : PlayableAsset, ITimelineClipAsset
{
    public ScriptActiveBehaviour template = new ScriptActiveBehaviour ();

    public ClipCaps clipCaps
    {
        get { return ClipCaps.Blending; }
    }

    public override Playable CreatePlayable (PlayableGraph graph, GameObject owner)
    {
        var playable = ScriptPlayable<ScriptActiveBehaviour>.Create (graph, template);
        return playable;
    }
}
