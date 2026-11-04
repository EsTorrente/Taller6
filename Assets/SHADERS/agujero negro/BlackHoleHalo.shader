// Glow around the core (on BH_Reflection, pushed outward). The brightness comes from how close each
// view ray passes to the core's edge, so the ring always hugs the silhouette from any angle.
Shader "ESCENA67/BlackHoleHalo"
{
    Properties
    {
        _GlowColor ("Glow Color", Color) = (1, 0.45, 0.15, 1)
        _HotColor ("Hot Color", Color) = (1, 0.93, 0.78, 1)
        _Intensity ("Intensity", Float) = 1.6
        _Falloff ("Falloff (higher = tighter)", Float) = 4
        _InnerRim ("Inner Rim Width", Range(0.01, 0.5)) = 0.12
        _CoreRatio ("Core Size / This Sphere", Range(0.1, 1)) = 0.84
        _HaloSize ("Halo Size", Float) = 0.6
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Blend One One
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _GlowColor;
                float4 _HotColor;
                float _Intensity;
                float _Falloff;
                float _InnerRim;
                float _CoreRatio;
                float _HaloSize;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                // push the shell out so the glow can reach past the core
                float3 p = v.positionOS.xyz * (1 + _HaloSize);
                o.positionWS = TransformObjectToWorld(p);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float3 centre = (unity_RendererBounds_Min.xyz + unity_RendererBounds_Max.xyz) * 0.5;
                float coreR = length(unity_RendererBounds_Max.xyz - unity_RendererBounds_Min.xyz) * 0.2887 * _CoreRatio;

                // how close this view ray passes to the core's centre, in core radii
                float3 cam = _WorldSpaceCameraPos;
                float3 d = normalize(i.positionWS - cam);
                float3 oc = centre - cam;
                float x = length(oc - d * dot(oc, d)) / coreR;

                float outside = exp(-max(x - 1, 0) * _Falloff);              // ring fading outward
                float inside = smoothstep(1 - _InnerRim, 1, x);               // thin bright rim on the core
                float g = x >= 1 ? outside : inside;
                float3 col = lerp(_GlowColor.rgb, _HotColor.rgb, g * g) * g * _Intensity;
                return half4(col, 0);
            }
            ENDHLSL
        }
    }
}
