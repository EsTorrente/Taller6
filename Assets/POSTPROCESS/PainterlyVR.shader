Shader "Hidden/PainterlyVR"
{
    Properties
    {
        _BrushTex ("Brush Atlas 6x6 (Grayscale)", 2D) = "gray" {}
        _CanvasTex ("Canvas Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "LiveWaterColor"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.5

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_BrushTex);  SAMPLER(sampler_BrushTex);
            TEXTURE2D(_CanvasTex); SAMPLER(sampler_CanvasTex);

            float _StrokeScale;
            float _StrokeStrength;
            float _StrokeAngle;
            float _WashIntensity;
            float _EdgeDarkening;
            float _ColorBleed;
            float _CanvasScale;
            float _CanvasStrength;
            float _NearWeight;
            float _FarWeight;
            float _FadeStart;
            float _FadeEnd;
            float _AnimateSpeed;

            half3 SrcColor(float2 uv)
            {
                return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
            }

            half4 Frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float2 uv = i.texcoord;
                float2 texel = _BlitTexture_TexelSize.xy;
                half3 src = SrcColor(uv);

                float raw = SampleSceneDepth(uv);
                #if UNITY_REVERSED_Z
                    if (raw < 1e-5) return half4(src, 1);
                #else
                    if (raw > 1.0 - 1e-5) return half4(src, 1);
                #endif

                float eyeDepth = LinearEyeDepth(raw, _ZBufferParams);
                float3 wp = ComputeWorldSpacePosition(uv, raw, UNITY_MATRIX_I_VP);
                float3 viewDir = normalize(wp - _WorldSpaceCameraPos);

                // Surface normal from depth derivatives
                float3 n = normalize(cross(ddy(wp), ddx(wp)));
                n = dot(n, viewDir) > 0 ? -n : n;

                // Surface-aligned frame
                float3 up = abs(n.y) > 0.95 ? float3(0, 0, 1) : float3(0, 1, 0);
                float3 T = normalize(cross(up, n));
                float3 B = cross(n, T);
                float sn, cs;
                sincos(_StrokeAngle, sn, cs);
                float3 T2 = T * cs + B * sn;
                float3 B2 = B * cs - T * sn;

                // World-anchored UVs with live animation shimmer
                float2 suv = float2(dot(wp, T2), dot(wp, B2)) * _StrokeScale;
                suv += _AnimateSpeed * float2(0.37, 0.19) * floor(_Time.y * 6.0) * 0.15;

                // 6x6 Atlas lookup function
                float2 cell = floor(suv);
                float2 localUV = frac(suv);
                float hash = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
                float tileIndex = floor(hash * 36.0);
                tileIndex = clamp(tileIndex, 0.0, 35.0);
                float tileY = floor(tileIndex / 6.0);
                float tileX = tileIndex - (tileY * 6.0);
                float2 atlasBaseUV = float2(tileX, tileY) / 6.0;

                // Multi-tap watercolor wash & gradient sampling (KinoAqua / flockaroo wash style)
                const float e = 1.0 / 128.0;
                float2 sampleUV = atlasBaseUV + localUV / 6.0;
                float h  = SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, sampleUV).r;
                float hx = SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, sampleUV + float2(e / 6.0, 0)).r;
                float hy = SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, sampleUV + float2(0, e / 6.0)).r;
                
                float2 grad = float2(hx - h, hy - h);
                float gradLen = length(grad);

                // Screen projection for organic wash displacement
                float3 tV = mul((float3x3)UNITY_MATRIX_V, T2);
                float3 bV = mul((float3x3)UNITY_MATRIX_V, B2);
                float2 projScale = 0.5 * float2(UNITY_MATRIX_P._m00, UNITY_MATRIX_P._m11);

                float2 disp = (grad.x * tV.xy + grad.y * bV.xy) * projScale / eyeDepth * _StrokeStrength * (h + 0.5);
                disp = clamp(disp, -texel * 32.0, texel * 32.0);

                // Watercolor multi-tap color bleeding (wet-on-dry wash mixing)
                half3 washCol = SrcColor(uv + disp);
                [unroll]
                for(int k = 1; k <= 3; k++)
                {
                    float offsetMult = (float)k * 1.5;
                    washCol += SrcColor(uv + disp + tV.xy * texel * offsetMult * _ColorBleed);
                    washCol += SrcColor(uv + disp - tV.xy * texel * offsetMult * _ColorBleed);
                }
                washCol /= 7.0;

                // Pigment pooling at stroke edges (darker outlines characteristic of dried watercolor)
                float edgeFactor = pow(saturate(gradLen * _EdgeDarkening), 1.5);
                washCol *= (1.0 - edgeFactor * 0.6);

                // Canvas / paper texture integration (mean-preserving multiply)
                float2 cuv = float2(dot(wp, T), dot(wp, B)) * _CanvasScale;
                half cv = SAMPLE_TEXTURE2D(_CanvasTex, sampler_CanvasTex, cuv).r;
                washCol *= 1.0 + (cv - 0.5) * 2.0 * _CanvasStrength;

                // Distance weighting / depth fade
                float t = saturate((eyeDepth - _FadeStart) / max(_FadeEnd - _FadeStart, 1e-3));
                float weight = lerp(_NearWeight, _FarWeight, t);

                return half4(lerp(src, washCol, weight * _WashIntensity), 1);
            }
            ENDHLSL
        }
    }
}