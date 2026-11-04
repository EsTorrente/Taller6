// Hand-drawn Pencil Outline - full-screen effect for Unity 6 / URP 17
// Use with: Renderer Asset > Add Renderer Feature > Full Screen Pass Renderer Feature
//   Requirements: Depth + Normal, Fetch Color Buffer ON
//
// Screen-space edge detection (depth + normals, like Flat Kit's Outline effect), then made to
// look hand-drawn: wobbling lines, several offset "stroke copies", breaks, pressure variation,
// paper grain and a stepped redraw rate.
Shader "Custom/Painterly/PencilOutline"
{
    Properties
    {
        [Header(Line)]
        _LineColor("Pencil Color", Color) = (0.16, 0.11, 0.14, 1)
        _Opacity("Line Opacity", Range(0, 1)) = 0.9
        _ColorBlend("Scene Color Blend (colored pencil)", Range(0, 1)) = 0.35
        _Thickness("Thickness (px at 1080p)", Range(0.5, 6)) = 1.5

        [Header(Edge Detection)]
        _DepthThreshold("Depth Sensitivity (lower = more lines)", Range(0.005, 0.5)) = 0.08
        _NormalThreshold("Normal Sensitivity (lower = more lines)", Range(0.05, 1.5)) = 0.3
        _InnerLines("Inner Line Strength", Range(0, 1)) = 0.8
        _FadeStart("Distance Fade Start", Float) = 60
        _FadeEnd("Distance Fade End", Float) = 200

        [Header(Hand Drawn)]
        _Wobble("Wobble (px)", Range(0, 8)) = 1.5
        _WobbleSize("Wobble Size (px)", Float) = 80
        [IntRange] _Copies("Stroke Copies", Range(1, 3)) = 2
        _ShiftRange("Stroke Shift (px)", Range(0, 8)) = 2
        _BreakAmount("Line Breaks", Range(0, 1)) = 0.3
        _BreakSize("Break Size (px)", Float) = 45
        _Pressure("Pressure Variation", Range(0, 1)) = 0.5
        _Grain("Pencil Grain", Range(0, 1)) = 0.6
        _GrainSize("Grain Size (px)", Range(0.5, 4)) = 1.2
        _Fps("Redraw FPS (0 = static)", Range(0, 24)) = 8
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off
        ZTest Always
        Cull Off
        Blend Off

        Pass
        {
            Name "PencilOutline"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragPencil
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _LineColor;
                half _Opacity;
                half _ColorBlend;
                float _Thickness;
                float _DepthThreshold;
                float _NormalThreshold;
                half _InnerLines;
                float _FadeStart;
                float _FadeEnd;
                float _Wobble;
                float _WobbleSize;
                float _Copies;
                float _ShiftRange;
                half _BreakAmount;
                float _BreakSize;
                half _Pressure;
                half _Grain;
                float _GrainSize;
                float _Fps;
            CBUFFER_END

            float Hash21(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            float2 Hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.xx + p3.yz) * p3.zy);
            }

            float VNoise2(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            // Roberts-cross edge detection on linear depth and normals.
            // o = half-size of the sampling cross in uv units (controls line thickness).
            float EdgeAt(float2 uv, float2 o, out float nearDist)
            {
                float2 uvA = uv + float2(-o.x, -o.y);
                float2 uvB = uv + float2( o.x,  o.y);
                float2 uvC = uv + float2( o.x, -o.y);
                float2 uvD = uv + float2(-o.x,  o.y);

                float dA = LinearEyeDepth(SampleSceneDepth(uvA), _ZBufferParams);
                float dB = LinearEyeDepth(SampleSceneDepth(uvB), _ZBufferParams);
                float dC = LinearEyeDepth(SampleSceneDepth(uvC), _ZBufferParams);
                float dD = LinearEyeDepth(SampleSceneDepth(uvD), _ZBufferParams);

                float dMin = min(min(dA, dB), min(dC, dD));
                float dMax = max(max(dA, dB), max(dC, dD));
                nearDist = dMin;

                // relative depth gradient: silhouettes and object-vs-object lines
                float dg = sqrt((dA - dB) * (dA - dB) + (dC - dD) * (dC - dD)) / max(dMin, 0.05);
                float depthEdge = smoothstep(_DepthThreshold, _DepthThreshold * 2.0, dg);

                // normal gradient: creases and inner lines (skipped where sky is involved)
                float3 nA = SampleSceneNormals(uvA);
                float3 nB = SampleSceneNormals(uvB);
                float3 nC = SampleSceneNormals(uvC);
                float3 nD = SampleSceneNormals(uvD);
                float ng1 = 1.0 - dot(nA, nB);
                float ng2 = 1.0 - dot(nC, nD);
                float ng = sqrt(ng1 * ng1 + ng2 * ng2);
                float notSky = dMax < _ProjectionParams.z * 0.98 ? 1.0 : 0.0;
                float normalEdge = smoothstep(_NormalThreshold, _NormalThreshold * 1.6, ng) * notSky * _InnerLines;

                return max(depthEdge, normalEdge);
            }

            half4 FragPencil(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 uv = input.texcoord;
                float3 src = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                float2 res = _ScreenParams.xy;
                float2 texel = 1.0 / res;
                float2 pix = uv * res;
                float scale = res.y / 1080.0;                       // resolution-independent sizes
                float key = _Fps > 0.01 ? floor(_Time.y * _Fps) : 0.0;
                int copies = (int)round(_Copies);

                float a = 0.0;

                [unroll]
                for (int k = 0; k < 3; k++)
                {
                    if (k < copies)
                    {
                        float seed = key * 1.7 + k * 19.3;

                        // each copy is its own slightly displaced, wobbling stroke
                        float2 shift = (Hash22(float2(seed, 3.1 + k)) - 0.5) * 2.0 * _ShiftRange * scale;
                        float2 wob = (float2(VNoise2(pix / _WobbleSize + seed),
                                             VNoise2(pix / _WobbleSize + seed + 41.7)) - 0.5) * 2.0 * _Wobble * scale;
                        float thick = _Thickness * scale * (0.8 + 0.4 * Hash21(float2(seed, 7.7)));

                        float2 uvk = uv + (shift + wob) * texel;
                        float nearDist;
                        float e = EdgeAt(uvk, thick * 0.5 * texel, nearDist);

                        // breaks: the pencil lifts off the paper
                        float brk = 1.0;
                        if (_BreakAmount > 0.001)
                        {
                            float bn = VNoise2(pix / _BreakSize + seed * 0.37 + k * 13.0);
                            float t = _BreakAmount * 0.9;
                            brk = smoothstep(t - 0.1, t + 0.1, bn);
                        }

                        // pressure: darker and lighter parts along the line
                        float pn = VNoise2(pix / (_BreakSize * 2.2) + seed * 0.21 + 9.1);
                        float pr = lerp(1.0, saturate(0.35 + 0.9 * pn), _Pressure);

                        float fade = 1.0 - smoothstep(_FadeStart, _FadeEnd, nearDist);
                        float w = (k == 0) ? 1.0 : 0.65;

                        // overlapping strokes build up darkness
                        a = 1.0 - (1.0 - a) * (1.0 - e * brk * pr * fade * w);
                    }
                }

                // graphite grain: static paper tooth that the line catches
                float g = Hash21(floor(pix / (_GrainSize * scale)));
                a *= lerp(1.0, smoothstep(0.15, 0.85, g), _Grain);
                a = saturate(a * _Opacity);

                float3 target = lerp(_LineColor.rgb, src * _LineColor.rgb * 2.2, _ColorBlend);
                return half4(lerp(src, target, a), 1.0);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
