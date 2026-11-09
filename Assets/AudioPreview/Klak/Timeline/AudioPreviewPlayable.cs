using UnityEngine;
using UnityEngine.Playables;
using System.Reflection;
using System;

namespace Klak.Timeline
{
    [Serializable]
    public class AudioPreviewPlayable : PlayableBehaviour
    {
        #region Serialized variables

        public AudioClip clip;

        #endregion

        #if UNITY_EDITOR

        #region PlayableBehaviour overrides

        public override void OnGraphStop(Playable playable)
        {
            if (clip != null) StopClip();
        }

        public override void ProcessFrame(Playable playable, FrameData info, object playerData)
        {
            // Edit-mode scrubbing only: in Play mode the real Audio Track already plays the song
            if (clip != null && !Application.isPlaying) PlayClip((float)playable.GetTime());
        }

        #endregion

        #region Audio clip utilities

        const float kMaxGap = 1.0f / 15;

        // Unity 2020.2+ names (the old GetClipPosition/PlayClip/StopAllClips no longer exist)
        static readonly Type kAudioUtil = Type.GetType("UnityEditor.AudioUtil,UnityEditor");
        static readonly MethodInfo kGetPosition = kAudioUtil.GetMethod("GetPreviewClipPosition", Type.EmptyTypes);
        static readonly MethodInfo kPlay = kAudioUtil.GetMethod("PlayPreviewClip", new [] { typeof(AudioClip), typeof(int), typeof(bool) });
        static readonly MethodInfo kSetPosition = kAudioUtil.GetMethod("SetPreviewClipSamplePosition", new [] { typeof(AudioClip), typeof(int) });
        static readonly MethodInfo kStopAll = kAudioUtil.GetMethod("StopAllPreviewClips", Type.EmptyTypes);

        float _lastUpdateTime;
        bool _played;

        float GetClipPosition()
        {
            return (float)kGetPosition.Invoke(null, null);
        }

        void CheckPosition()
        {
            // Stop if the gap is larger than kMaxGap.
            if (Mathf.Abs(GetClipPosition() - _lastUpdateTime) > kMaxGap) StopClip();
        }

        void PlayClip(float time)
        {
            // Stop and replay if the gap is larger than kMaxGap.
            if (Mathf.Abs(GetClipPosition() - time) > kMaxGap)
            {
                StopClip();

                kPlay.Invoke(null, new System.Object [] { clip, 0, false });
                kSetPosition.Invoke(null, new System.Object [] { clip, (int)(time * clip.frequency + 1) });

                UnityEditor.EditorApplication.update += CheckPosition;
                _played = true;
            }

            _lastUpdateTime = time;
        }

        void StopClip()
        {
            kStopAll.Invoke(null, null);

            if (!_played) return;

            UnityEditor.EditorApplication.update -= CheckPosition;
            _played = false;
        }

        #endregion

        #endif
    }
}
