using System;
using UnityEngine;
using UnityEngine.Playables;
using UnityEngine.Timeline;

public class ScriptActiveMixerBehaviour : PlayableBehaviour
{
    bool m_DefaultEnabled;

    bool m_AssignedEnabled;

    MonoBehaviour m_TrackBinding;

    public override void ProcessFrame(Playable playable, FrameData info, object playerData)
    {
        m_TrackBinding = playerData as MonoBehaviour;

        if (m_TrackBinding == null)
            return;

        if (m_TrackBinding.enabled != m_AssignedEnabled)
            m_DefaultEnabled = m_TrackBinding.enabled;

        int inputCount = playable.GetInputCount ();

        float totalWeight = 0f;
        float greatestWeight = 0f;
        int currentInputs = 0;

        for (int i = 0; i < inputCount; i++)
        {
            float inputWeight = playable.GetInputWeight(i);
            ScriptPlayable<ScriptActiveBehaviour> inputPlayable = (ScriptPlayable<ScriptActiveBehaviour>)playable.GetInput(i);
            ScriptActiveBehaviour input = inputPlayable.GetBehaviour ();
            
            totalWeight += inputWeight;

            if (inputWeight > greatestWeight)
            {
                m_AssignedEnabled = input.enabled;
                m_TrackBinding.enabled = m_AssignedEnabled;
                greatestWeight = inputWeight;
            }

            if (!Mathf.Approximately (inputWeight, 0f))
                currentInputs++;
        }

        if (currentInputs != 1 && 1f - totalWeight > greatestWeight)
        {
            m_TrackBinding.enabled = m_DefaultEnabled;
        }
    }
}
