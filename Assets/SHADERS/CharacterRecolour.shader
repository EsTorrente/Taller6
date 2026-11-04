Shader "Custom/CharacterRecolorToon"
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

        [Header(Rim Painterly Edge)]
        _RimWobble ("Edge Wobble", Range(0,1)) = 0.25
        _RimNoiseScale ("Noise Scale", Float) = 498.2
        _RimBoilSpeed ("Boil Speed", Range(0,10)) = 4.11
        [Toggle] _RimBoilStepped ("Stepped Boil", Float) = 1

        [Header(Foot Shadow)]
        _FootShadowStrength ("Strength (0 = off)", Range(0,1)) = 0
        _FootShadowColor ("Color", Color) = (0,0,0,1)
        _FootShadowStart ("Start Height (fully dark)", Float) = 0
        _FootShadowEnd ("End Height (no effect)", Float) = 0.5
        [Enum(Object Space, 0, World Space, 1)] _FootShadowSpace ("Height Space", Float) = 0
    }


    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }


        // =========================================================
        // MAIN TOON LIGHTING PASS
        // =========================================================

        Pass
        {
            Name "ToonForward"

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag


            // -----------------------------------------------------
            // LIGHT KEYWORDS
            // -----------------------------------------------------

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN

            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _FORWARD_PLUS


            // -----------------------------------------------------
            // URP LIBRARIES
            // -----------------------------------------------------

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


            // =====================================================
            // STRUCTURES
            // =====================================================

            struct Attributes
            {
                float4 positionOS : POSITION;

                float3 normalOS : NORMAL;

                float2 uv : TEXCOORD0;
            };


            struct Varyings
            {
                float4 positionCS : SV_POSITION;

                float3 positionWS : TEXCOORD1;

                float3 normalWS : TEXCOORD2;

                float2 uv : TEXCOORD3;

                float3 viewDirectionWS : TEXCOORD4;

                float4 shadowCoord : TEXCOORD5;

                float3 positionOS : TEXCOORD6;
            };


            // =====================================================
            // TEXTURES
            // =====================================================

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_MaskMap);
            SAMPLER(sampler_MaskMap);


            // Set globally by PainterlyRimLight.cs (not per material)
            float4 _PainterlyRimLightPos;
            float4 _PainterlyRimLightColor;


            // =====================================================
            // MATERIAL VARIABLES
            // =====================================================

            CBUFFER_START(UnityPerMaterial)

                float4 _BaseMap_ST;

                float4 _HairColor;
                float4 _SkinColor;
                float4 _EyeColor;

                float _HairStrength;
                float _SkinStrength;
                float _EyeStrength;

                float4 _ShadowColor;

                float _ShadowThreshold;
                float _ShadowSoftness;

                float _ShadowLightInfluence;

                float _LightIntensity;

                float4 _RimColor;

                float _RimPower;
                float _RimIntensity;

                float _RimLightInfluence;

                float _RimLightSource;
                float _RimShadowMask;

                float _RimThreshold;
                float _RimSoftness;
                float _RimWobble;
                float _RimNoiseScale;
                float _RimBoilSpeed;
                float _RimBoilStepped;

                float _RimMode;
                float _RimLightOffset;
                float _RimShadowBias;

                float _FootRimMask;
                float _FootShadowSpace;
                float4 _FootShadowColor;
                float _FootShadowStrength;
                float _FootShadowStart;
                float _FootShadowEnd;

            CBUFFER_END


            // =====================================================
            // PROCEDURAL NOISE (object space, for the boiling rim edge)
            // =====================================================

            float Hash13(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }

            float VNoise(float3 p)
            {
                float3 i = floor(p);
                float3 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);

                float a = lerp(lerp(Hash13(i),                 Hash13(i + float3(1,0,0)), f.x),
                               lerp(Hash13(i + float3(0,1,0)), Hash13(i + float3(1,1,0)), f.x), f.y);

                float b = lerp(lerp(Hash13(i + float3(0,0,1)), Hash13(i + float3(1,0,1)), f.x),
                               lerp(Hash13(i + float3(0,1,1)), Hash13(i + float3(1,1,1)), f.x), f.y);

                return lerp(a, b, f.z);
            }

            float FBM(float3 p)
            {
                float v = 0.0;
                float a = 0.5;

                [unroll]
                for (int k = 0; k < 3; k++)
                {
                    v += a * VNoise(p);
                    p = p * 2.03 + 17.1;
                    a *= 0.5;
                }

                return v / 0.875;
            }

            // A new noise pattern per keyframe (integer part of t),
            // cross-faded smoothly, or snapped when Stepped Boil is on.
            float3 KeyOffset(float k)
            {
                return float3(
                    Hash13(float3(k, 1.7, 3.1)),
                    Hash13(float3(k, 5.3, 9.2)),
                    Hash13(float3(k, 2.9, 7.7))
                ) * 53.0;
            }

            float FBMT(float3 p, float t)
            {
                float k = floor(t);
                float a = FBM(p + KeyOffset(k));

                if (_RimBoilStepped > 0.5)
                    return a;

                float b = FBM(p + KeyOffset(k + 1.0));

                return lerp(a, b, smoothstep(0.0, 1.0, frac(t)));
            }


            // =====================================================
            // VERTEX
            // =====================================================

            Varyings vert(Attributes IN)
            {
                Varyings OUT;


                // World position
                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(IN.positionOS.xyz);


                OUT.positionCS = positionInputs.positionCS;

                OUT.positionWS = positionInputs.positionWS;

                OUT.positionOS = IN.positionOS.xyz;


                // World normal
                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(IN.normalOS);


                OUT.normalWS =
                    normalize(normalInputs.normalWS);


                // UV
                OUT.uv =
                    TRANSFORM_TEX(IN.uv, _BaseMap);


                // Camera direction
                OUT.viewDirectionWS =
                    GetWorldSpaceNormalizeViewDir(
                        OUT.positionWS
                    );


                // Shadow coordinates
                OUT.shadowCoord =
                    GetShadowCoord(positionInputs);


                return OUT;
            }


            // =====================================================
            // RECOLOR FUNCTION
            // =====================================================

            half3 ApplyRecolor(
                half3 original,
                half3 mask,
                half3 result
            )
            {
                half hairMask = mask.r;
                half skinMask = mask.g;
                half eyeMask  = mask.b;


                // Hair
                result = lerp(
                    result,
                    original * _HairColor.rgb,
                    hairMask * _HairStrength
                );


                // Skin
                result = lerp(
                    result,
                    original * _SkinColor.rgb,
                    skinMask * _SkinStrength
                );


                // Eyes
                result = lerp(
                    result,
                    original * _EyeColor.rgb,
                    eyeMask * _EyeStrength
                );


                return result;
            }


            // =====================================================
            // TOON LIGHT FUNCTION
            // =====================================================

            half3 ToonLight(
                half3 baseColor,
                half3 normalWS,
                half3 lightDirection,
                half3 lightColor,
                half lightAttenuation
            )
            {
                // ---------------------------------------------
                // N dot L
                // ---------------------------------------------

                half NdotL =
                    saturate(
                        dot(
                            normalWS,
                            lightDirection
                        )
                    );


                // Apply light/shadow attenuation
                half lighting =
                    NdotL * lightAttenuation;


                // ---------------------------------------------
                // Toon threshold
                // ---------------------------------------------

                half toonBand =
                    smoothstep(
                        _ShadowThreshold - _ShadowSoftness,
                        _ShadowThreshold + _ShadowSoftness,
                        lighting
                    );


                // ---------------------------------------------
                // Shadow colour influenced by light colour
                // ---------------------------------------------

                half3 lightInfluencedShadow =
                    lerp(
                        _ShadowColor.rgb,
                        _ShadowColor.rgb * lightColor,
                        _ShadowLightInfluence
                    );


                // ---------------------------------------------
                // Blend shadow → light
                // ---------------------------------------------

                half3 toonColor =
                    lerp(
                        baseColor * lightInfluencedShadow,
                        baseColor * lightColor * _LightIntensity,
                        toonBand
                    );


                return toonColor;
            }


            // =====================================================
            // FRAGMENT
            // =====================================================

            half4 frag(Varyings IN) : SV_Target
            {
                // =================================================
                // TEXTURES
                // =================================================

                half4 baseTexture =
                    SAMPLE_TEXTURE2D(
                        _BaseMap,
                        sampler_BaseMap,
                        IN.uv
                    );


                half4 mask =
                    SAMPLE_TEXTURE2D(
                        _MaskMap,
                        sampler_BaseMap,
                        IN.uv
                    );


                // =================================================
                // RECOLOR CHARACTER
                // =================================================

                half3 baseColor =
                    ApplyRecolor(
                        baseTexture.rgb,
                        mask.rgb,
                        baseTexture.rgb
                    );


                // =================================================
                // NORMAL
                // =================================================

                half3 normalWS =
                    normalize(IN.normalWS);


                // =================================================
                // MAIN LIGHT
                // =================================================

                // Shadow coordinate per pixel (the cascade is chosen per pixel).
                // Screen space shadows already provide a screen coordinate.
                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                    float4 shadowCoord = IN.shadowCoord;
                #else
                    float4 shadowCoord =
                        TransformWorldToShadowCoord(IN.positionWS);
                #endif


                Light mainLight =
                    GetMainLight(shadowCoord);


                // Main light direction
                half3 mainLightDirection =
                    normalize(mainLight.direction);


                // Main light attenuation
                half mainAttenuation =
                    mainLight.shadowAttenuation *
                    mainLight.distanceAttenuation;


                // Toon main lighting
                half3 finalColor =
                    ToonLight(
                        baseColor,
                        normalWS,
                        mainLightDirection,
                        mainLight.color,
                        mainAttenuation
                    );


                // =================================================
                // ADDITIONAL LIGHTS
                // =================================================

                #if defined(_ADDITIONAL_LIGHTS)


                    InputData inputData =
                        (InputData)0;


                    inputData.positionWS =
                        IN.positionWS;


                    inputData.normalWS =
                        normalWS;


                    inputData.viewDirectionWS =
                        IN.viewDirectionWS;


                    inputData.normalizedScreenSpaceUV =
                        GetNormalizedScreenSpaceUV(
                            IN.positionCS
                        );


                    // ---------------------------------------------
                    // Forward+ directional lights
                    // ---------------------------------------------

                    #if USE_FORWARD_PLUS

                    UNITY_LOOP

                    for (
                        uint lightIndex = 0;

                        lightIndex <
                        min(
                            URP_FP_DIRECTIONAL_LIGHTS_COUNT,
                            MAX_VISIBLE_LIGHTS
                        );

                        lightIndex++
                    )
                    {
                        Light light =
                            GetAdditionalLight(
                                lightIndex,
                                IN.positionWS,
                                half4(1,1,1,1)
                            );


                        finalColor +=
                            ToonLight(
                                baseColor,
                                normalWS,
                                normalize(light.direction),
                                light.color,
                                light.distanceAttenuation *
                                light.shadowAttenuation
                            );
                    }

                    #endif


                    // ---------------------------------------------
                    // Regular additional lights
                    // ---------------------------------------------

                    uint pixelLightCount =
                        GetAdditionalLightsCount();


                    LIGHT_LOOP_BEGIN(pixelLightCount)

                        Light light =
                            GetAdditionalLight(
                                lightIndex,
                                IN.positionWS,
                                half4(1,1,1,1)
                            );


                        finalColor +=
                            ToonLight(
                                baseColor,
                                normalWS,
                                normalize(light.direction),
                                light.color,
                                light.distanceAttenuation *
                                light.shadowAttenuation
                            );

                    LIGHT_LOOP_END

                #endif


                // =================================================
                // RIM LIGHT
                // =================================================

                half3 viewDirection =
                    normalize(IN.viewDirectionWS);


                // 0 when looking directly at surface
                // 1 around the silhouette
                half rim =
                    1.0 -
                    saturate(
                        dot(
                            normalWS,
                            viewDirection
                        )
                    );


                // Make rim sharper/softer
                rim =
                    pow(
                        rim,
                        _RimPower
                    );


                // Which light drives the rim: the main light,
                // or the Light picked with the PainterlyRimLight component
                half3 rimLightDirection = mainLightDirection;
                half3 rimLightColor = mainLight.color;

                if (_RimLightSource > 0.5)
                {
                    // w = 0: directional (xyz = direction toward the light)
                    // w = 1: point/spot (xyz = position)
                    float3 toLight =
                        _PainterlyRimLightPos.xyz -
                        IN.positionWS * _PainterlyRimLightPos.w;

                    rimLightDirection = normalize(toLight + 1e-5);
                    rimLightColor = _PainterlyRimLightColor.rgb;
                }


                // Light influence on rim
                half rimLightFacing =
                    saturate(
                        dot(
                            normalWS,
                            rimLightDirection
                        )
                    );


                // More rim on the darker/back-facing side
                half rimFromLight =
                    1.0 -
                    rimLightFacing;


                rim *= rimFromLight;


                // Light Edge: a band around where the surface turns away from the light.
                // Depends only on the light and the surface, never on the camera.
                if (_RimMode > 1.5)
                {
                    // Lit Edge: outline glow, only on the side of the object that faces the light.
                    // "Light Edge Position" sets how far into the lit side it starts.
                    half litSide =
                        smoothstep(
                            _RimLightOffset - 0.1,
                            _RimLightOffset + 0.3,
                            dot(normalWS, rimLightDirection)
                        );

                    rim =
                        pow(
                            max(
                                1.0 - saturate(dot(normalWS, viewDirection)),
                                1e-4
                            ),
                            _RimPower
                        ) * litSide;
                }
                else if (_RimMode > 0.5)
                {
                    half band =
                        saturate(
                            1.0 -
                            abs(
                                dot(normalWS, rimLightDirection) -
                                _RimLightOffset
                            )
                        );

                    rim = pow(band, _RimPower);
                }


                // Painterly band: threshold + softness, with a ragged edge
                // that wobbles (boils) over time
                float rimNoise =
                    _RimWobble > 0.001
                    ? FBMT(
                        IN.positionOS * _RimNoiseScale,
                        _Time.y * _RimBoilSpeed
                    )
                    : 0.5;

                float rimSoft = max(_RimSoftness, 0.001);

                rim =
                    smoothstep(
                        _RimThreshold - rimSoft,
                        _RimThreshold + rimSoft,
                        rim + (rimNoise - 0.5) * _RimWobble
                    );


                // Hide the rim inside shadows cast onto the character by other objects.
                // This always uses the MAIN light's shadow map (the scene's shadows),
                // whichever light drives the rim, so it also works with a Custom Light.
                // The lookup is pushed out along the normal so the character's own
                // surface does not shadow itself (speckles on the rim).
                half rimShadow = 1.0;

                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                    rimShadow = mainLight.shadowAttenuation;
                #else
                    rimShadow =
                        MainLightRealtimeShadow(
                            TransformWorldToShadowCoord(
                                IN.positionWS +
                                normalWS * _RimShadowBias
                            )
                        );
                #endif


                // A little contrast so the rim is cut off like a painted shadow edge
                rimShadow = smoothstep(0.15, 0.85, rimShadow);


                // Pixels turned away from the main light are always inside the
                // character's own shadow in the shadow map, so they keep their rim
                half rimShadowWeight =
                    smoothstep(
                        -0.15,
                        0.1,
                        dot(normalWS, mainLightDirection)
                    ) * _RimShadowMask;


                rim *= lerp(1.0, rimShadow, rimShadowWeight);


                // Foot shadow gradient: 1 at and below Start, 0 at and above End.
                // Also used to mask the rim out of that area.
                float footHeight =
                    _FootShadowSpace > 0.5
                    ? IN.positionWS.y
                    : IN.positionOS.y;

                float footMask =
                    1.0 -
                    smoothstep(
                        _FootShadowStart,
                        max(_FootShadowEnd, _FootShadowStart + 1e-4),
                        footHeight
                    );


                // Hide the rim wherever the foot shadow is set up
                // (uses the gradient area itself, even if Strength is 0)
                rim *= 1.0 - footMask * _FootRimMask;


                // Use main light colour
                half3 finalRimColor =
                    lerp(
                        _RimColor.rgb,
                        _RimColor.rgb * rimLightColor,
                        _RimLightInfluence
                    );


                finalColor +=
                    finalRimColor *
                    rim *
                    _RimIntensity;


                // =================================================
                // FOOT SHADOW (top-to-bottom gradient)
                // =================================================

                finalColor =
                    lerp(
                        finalColor,
                        _FootShadowColor.rgb,
                        footMask * _FootShadowStrength
                    );


                // =================================================
                // OUTPUT
                // =================================================

                return half4(
                    finalColor,
                    baseTexture.a
                );
            }

            ENDHLSL
        }


        // =========================================================
        // SHADOW CASTING
        // =========================================================

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}