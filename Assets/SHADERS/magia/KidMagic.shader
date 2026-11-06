// Kids (Body_child, Clothes, Hair, Eyes...): the Character Recolor Toon shader (Unity 6 / URP 17) plus the Blender
// "Kid_Magic" appear / disappear. The surface is exactly CharacterRecolorToon; the only additions are the dissolve
// (discard + glow band), its properties, and the dissolve clip in the shadow / depth passes.
// Both kids share one material; the cut follows the KidChange empty through MagicDissolveDriver, which also gives
// each kid its own Mapping Location X. Defaults are the Blender values.
//
// Character Recolor Toon notes: no boiling FBM noise on the rim edge, own ShadowCaster pass (UsePass of URP/Lit broke
// SRP Batcher compatibility), unused interpolators and keyword variants removed.
Shader "ESCENA67/KidMagic"
{
    Properties
    {
        [Header(Textures)]
        _BaseMap ("Base Texture", 2D) = "white" {}
        _MaskMap ("RGB Mask (R Hair, G Skin, B Eyes)", 2D) = "black" {}

        [Header(Character Colors)]
        _HairColor ("Hair Color", Color) = (1,1,1,1)
        _SkinColor ("Skin Color", Color) = (1,1,1,1)
        _EyeColor ("Eye Color", Color) = (1,1,1,1)
        _HairStrength ("Hair Strength", Range(0,1)) = 0.922
        _SkinStrength ("Skin Strength", Range(0,1)) = 0.925
        _EyeStrength ("Eye Strength", Range(0,1)) = 0.923

        [Header(Lighting)]
        _LightIntensity ("Light Intensity", Range(0,2)) = 0.8
        _ShadowColor ("Shadow Color", Color) = (0.341,0.384,0.792,1)
        _ShadowThreshold ("Shadow Threshold", Range(0,1)) = 0.55
        _ShadowSoftness ("Shadow Softness", Range(0,0.5)) = 0.029
        _ShadowLightInfluence ("Shadow Light Color Influence", Range(0,1)) = 0

        [Header(Rim Light)]
        [Enum(Main Light, 0, Custom Light, 1)] _RimLightSource ("Rim Light Source", Float) = 0
        [Enum(View Edge Dark Side, 0, Light Band At Shadow Edge, 1, Lit Edge Facing The Light, 2)] _RimMode ("Rim Type", Float) = 2
        _RimColor ("Rim Color", Color) = (1,0.651,0.627,1)
        _RimIntensity ("Rim Intensity", Range(0,3)) = 0.08
        _RimPower ("Rim Width (Power)", Range(0.5,8)) = 5.56
        _RimThreshold ("Rim Threshold", Range(0,1)) = 0.194
        _RimSoftness ("Rim Softness", Range(0,0.5)) = 0
        _RimLightOffset ("Light Edge Position", Range(-1,1)) = 0
        _RimLightInfluence ("Rim Light Color Influence", Range(0,1)) = 1

        [Header(Rim Shadows)]
        _RimShadowMask ("Hidden By Cast Shadows", Range(0,1)) = 1
        _RimShadowBias ("Cast Shadow Bias", Range(0,0.2)) = 0.03
        _FootRimMask ("Hidden In Foot Shadow", Range(0,1)) = 1

        [Header(Foot Shadow)]
        _FootShadowStrength ("Strength (0 = off)", Range(0,1)) = 0
        _FootShadowColor ("Color", Color) = (0,0,0,1)
        _FootShadowStart ("Start Height (fully dark)", Float) = 0
        _FootShadowEnd ("End Height (no effect)", Float) = 0.5
        [Enum(Object Space, 0, World Space, 1)] _FootShadowSpace ("Height Space", Float) = 0

        [HideInInspector] _MagicMapLocation ("Mapping Location (X is set per kid by MagicDissolveDriver)", Vector) = (0, 0, 0, 0)
        [HideInInspector] _MagicMapRotation ("Mapping Rotation (radians)", Vector) = (0, 1.5708, 0, 0)
        [HideInInspector] _MagicMapScale ("Mapping Scale", Vector) = (1, 1, 0.9524, 0)
        [HideInInspector] _MagicNoiseMix ("Noise -> Gradient Mix", Range(0, 1)) = 0.9167
        [HideInInspector] _MagicNoiseScale ("Noise Scale", Float) = 10
        [HideInInspector] _MagicNoiseDetail ("Noise Detail (Blender uses 15)", Range(0, 15)) = 4
        [HideInInspector] _MagicNoiseRoughness ("Noise Roughness", Range(0, 1)) = 0.5
        [HideInInspector] _MagicNoiseW ("Noise W", Float) = 0
        [HideInInspector] _MagicNoiseWPerFrame ("Noise W per Frame", Float) = 0.0208333
        [HideInInspector] _MagicCut ("Cut Ramp (visible at, hidden at)", Vector) = (0.5, 0.536, 0, 0)
        [HideInInspector] _MagicEdge ("Glow Ramp (start, peak, end)", Vector) = (0.4, 0.515, 0.6, 0)
        [Header(Magic Glow)] _MagicGlowColorA ("Glow Color 1", Color) = (0.8227, 0, 1, 1)
        _MagicGlowColorB ("Glow Color 2", Color) = (1, 0.8063, 0.1231, 1)
        [HideInInspector] _MagicGlowColorRamp ("Glow Color Ramp Positions", Vector) = (0.3, 0.7, 0, 0)
        [HideInInspector] _MagicGlowNoiseScale ("Glow Color Noise Scale", Float) = 4
        [HideInInspector] _MagicGlowNoiseDetail ("Glow Color Noise Detail", Range(0, 15)) = 2
        [HideInInspector] _MagicSparkleScale ("Sparkle Scale", Float) = 60
        [HideInInspector] _MagicSparkleDetail ("Sparkle Detail", Range(0, 15)) = 2
        [HideInInspector] _MagicSparkleW ("Sparkle W", Float) = 0
        [HideInInspector] _MagicSparkleWPerFrame ("Sparkle W per Frame", Float) = 0.0833333
        [HideInInspector] _MagicSparkleRamp ("Sparkle Ramp (pos 1, pos 2, value 1, value 2)", Vector) = (0.45, 0.75, 0.35, 3)
        _MagicGlowStrength ("Glow Strength", Float) = 10
    }

    SubShader
    {
        // AlphaTest queue: the dissolve uses discard, so draw after the opaque geometry
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "MagicDissolveInput.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_MaskMap);   // sampled with sampler_BaseMap (saves a sampler slot)

        // Set globally by PainterlyRimLight.cs (not per material)
        float4 _PainterlyRimLightPos;
        float4 _PainterlyRimLightColor;

        // Identical in every pass => SRP Batcher compatible.
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;

            half4 _HairColor;
            half4 _SkinColor;
            half4 _EyeColor;
            half _HairStrength;
            half _SkinStrength;
            half _EyeStrength;

            half4 _ShadowColor;
            half _ShadowThreshold;
            half _ShadowSoftness;
            half _ShadowLightInfluence;
            half _LightIntensity;

            half4 _RimColor;
            half _RimPower;
            half _RimIntensity;
            half _RimLightInfluence;
            half _RimLightSource;
            half _RimShadowMask;
            half _RimThreshold;
            half _RimSoftness;
            half _RimMode;
            half _RimLightOffset;
            half _RimShadowBias;

            half _FootRimMask;
            half _FootShadowSpace;
            half4 _FootShadowColor;
            half _FootShadowStrength;
            float _FootShadowStart;
            float _FootShadowEnd;
            MAGIC_DISSOLVE_CBUFFER
        CBUFFER_END

        #include "MagicDissolve.hlsl"
        ENDHLSL

        // =========================================================
        // MAIN TOON LIGHTING PASS
        // =========================================================
        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing

            // One combined keyword line (the original had three separate ones = 8 combos, now 3).
            // Screen-space shadows dropped: not used on standalone VR.
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            // Forward+ keyword: _FORWARD_PLUS on Unity 6.0, _CLUSTER_LIGHT_LOOP on 6.1+.
            // Delete the one you don't need to halve the variant count.
            #pragma multi_compile _ _FORWARD_PLUS _CLUSTER_LIGHT_LOOP

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
                half3  viewDirWS  : TEXCOORD3;
                float  footHeight : TEXCOORD4;
                float3 magicP : TEXCOORD5; // noise-space position, interpolated
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs vp = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = vp.positionCS;
                OUT.positionWS = vp.positionWS;
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.viewDirWS = half3(GetWorldSpaceNormalizeViewDir(vp.positionWS));
                OUT.footHeight = _FootShadowSpace > 0.5h ? vp.positionWS.y : IN.positionOS.y;
                OUT.magicP = MagicPoint(vp.positionWS);
                return OUT;
            }

            // Sequential hair -> skin -> eyes recolor (same result as the original)
            half3 ApplyRecolor(half3 original, half3 mask)
            {
                half3 result = original;
                result = lerp(result, original * _HairColor.rgb, mask.r * _HairStrength);
                result = lerp(result, original * _SkinColor.rgb, mask.g * _SkinStrength);
                result = lerp(result, original * _EyeColor.rgb,  mask.b * _EyeStrength);
                return result;
            }

            half3 ToonLight(half3 baseColor, half3 N, half3 L, half3 lightColor, half attenuation)
            {
                half lighting = saturate(dot(N, L)) * attenuation;
                half toonBand = smoothstep(_ShadowThreshold - _ShadowSoftness,
                                           _ShadowThreshold + _ShadowSoftness,
                                           lighting);
                half3 shadowTint = lerp(_ShadowColor.rgb, _ShadowColor.rgb * lightColor, _ShadowLightInfluence);
                return lerp(baseColor * shadowTint, baseColor * lightColor * _LightIntensity, toonBand);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                // Dissolve FIRST: discarded pixels never pay for textures / lighting.
                MagicDissolveData magic = MagicDissolveP(IN.magicP);
                MagicClip(magic, IN.positionCS.xy);
                half3 glow = (half3)magic.glow;

                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 mask = SAMPLE_TEXTURE2D(_MaskMap, sampler_BaseMap, IN.uv).rgb;
                half3 baseColor = ApplyRecolor(baseTex.rgb, mask);

                half3 N = NormalizeNormalPerPixel(IN.normalWS);
                half3 V = half3(normalize(IN.viewDirWS));

                // ---- main light
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 L = mainLight.direction;

                half3 finalColor = ToonLight(baseColor, N, L, mainLight.color,
                                             (half)(mainLight.shadowAttenuation * mainLight.distanceAttenuation));

                // ---- additional lights (no per-light shadows)
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                    uint pixelLightCount = GetAdditionalLightsCount();

                    #if USE_FORWARD_PLUS || USE_CLUSTER_LIGHT_LOOP
                    [loop] for (uint fpIndex = 0; fpIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); fpIndex++)
                    {
                        Light light = GetAdditionalLight(fpIndex, IN.positionWS);
                        finalColor += ToonLight(baseColor, N, light.direction, light.color,
                                                (half)(light.distanceAttenuation * light.shadowAttenuation));
                    }
                    #endif

                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                        finalColor += ToonLight(baseColor, N, light.direction, light.color,
                                                (half)(light.distanceAttenuation * light.shadowAttenuation));
                    LIGHT_LOOP_END
                }
                #endif

                // ---- foot shadow gradient: 1 at/below Start, 0 at/above End (also masks the rim)
                half footMask = (half)(1.0 - smoothstep(_FootShadowStart,
                                                        max(_FootShadowEnd, _FootShadowStart + 1e-4),
                                                        IN.footHeight));

                // ---- rim light
                if (_RimIntensity > 0.001h)
                {
                    half3 Lr = L;
                    half3 Cr = mainLight.color;
                    if (_RimLightSource > 0.5h)
                    {
                        // w = 0: directional (xyz = direction toward the light), w = 1: point/spot (xyz = position)
                        float3 toLight = _PainterlyRimLightPos.xyz - IN.positionWS * _PainterlyRimLightPos.w;
                        Lr = half3(normalize(toLight + 1e-5));
                        Cr = _PainterlyRimLightColor.rgb;
                    }

                    half NoLr = dot(N, Lr);
                    half fres = 1.0h - saturate(dot(N, V));
                    half rimRaw;
                    if (_RimMode > 1.5h)
                    {
                        // Lit Edge: outline glow only on the side facing the light
                        half litSide = smoothstep(_RimLightOffset - 0.1h, _RimLightOffset + 0.3h, NoLr);
                        rimRaw = pow(max(fres, 1e-4h), _RimPower) * litSide;
                    }
                    else if (_RimMode > 0.5h)
                    {
                        // Light Edge: band where the surface turns away from the light
                        half band = saturate(1.0h - abs(NoLr - _RimLightOffset));
                        rimRaw = pow(max(band, 1e-4h), _RimPower);
                    }
                    else
                    {
                        // View Edge Dark Side
                        rimRaw = pow(max(fres, 1e-4h), _RimPower) * (1.0h - saturate(NoLr));
                    }

                    half rimSoft = max(_RimSoftness, 0.001h);
                    half rim = smoothstep(_RimThreshold - rimSoft, _RimThreshold + rimSoft, rimRaw);
                    rim *= 1.0h - footMask * _FootRimMask;

                    // Hide the rim inside shadows cast by other objects. The extra shadow lookup
                    // (pushed out along the normal to avoid self-shadow speckle) only runs on pixels
                    // that actually have rim.
                    if (rim > 0.001h && _RimShadowMask > 0.001h)
                    {
                        half rimShadowWeight = smoothstep(-0.15h, 0.1h, dot(N, L)) * _RimShadowMask;
                        if (rimShadowWeight > 0.001h)
                        {
                            half rimShadow = MainLightRealtimeShadow(
                                TransformWorldToShadowCoord(IN.positionWS + N * _RimShadowBias));
                            rimShadow = smoothstep(0.15h, 0.85h, rimShadow);
                            rim *= lerp(1.0h, rimShadow, rimShadowWeight);
                        }
                    }

                    half3 rimColor = lerp(_RimColor.rgb, _RimColor.rgb * Cr, _RimLightInfluence);
                    finalColor += rimColor * (rim * _RimIntensity);
                }

                // ---- foot shadow
                finalColor = lerp(finalColor, _FootShadowColor.rgb, footMask * _FootShadowStrength);

                // ---- magic glow band at the cut (emissive, on top of the toon result)
                finalColor += glow;

                return half4(finalColor, baseTex.a);
            }
            ENDHLSL
        }

        // =========================================================
        // SHADOW CASTING
        // Own pass instead of UsePass "Universal Render Pipeline/Lit/ShadowCaster":
        // UsePass pulls in Lit's material constant buffer, which makes this shader
        // SRP Batcher incompatible.
        // =========================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 magicP : TEXCOORD0;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.magicP = MagicPoint(positionWS); // before the shadow bias moves positionWS
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif
                float4 posCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    posCS.z = max(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.positionCS = posCS;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // Cheap: gradient only, no noise (shadows don't need the ragged edge)
                MagicClip(MagicDissolveCheap(i.magicP), i.positionCS.xy);
                return 0;
            }
            ENDHLSL
        }

        // =========================================================
        // DEPTH ONLY (depth prepass / depth priming / camera depth texture)
        // =========================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 magicP : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.magicP = MagicPoint(positionWS);
                return o;
            }

            half frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                // Full dissolve (same as Forward), or pixels discarded in Forward would still write depth
                MagicClip(MagicDissolveP(i.magicP), i.positionCS.xy);
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
