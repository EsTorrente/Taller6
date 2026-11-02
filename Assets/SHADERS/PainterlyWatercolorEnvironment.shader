// Painterly Watercolor Environment (Unity 6 / URP 17)
// Base color + normal map, watercolor shadows with brush strokes, painted rim light,
// metallic/roughness, and boiling color-bleed edges (inner edge band + outer bleed shell).
Shader "Custom/Painterly/WatercolorEnvironment"
{
    Properties
    {
        [Header(Textures)]
        [MainTexture] _BaseMap("Base Texture", 2D) = "white" {}
        [MainColor] _BaseColor("Tint", Color) = (1,1,1,1)
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Strength", Range(0, 3)) = 1

        [Header(Surface)]
        _Metallic("Metallic", Range(0, 1)) = 0
        _Roughness("Roughness", Range(0, 1)) = 1

        [Header(Lighting)]
        _LightIntensity("Light Intensity", Range(0, 2)) = 1
        _ShadowThreshold("Shadow Threshold", Range(0, 1)) = 0.5
        _ShadowSoftness("Wash Softness", Range(0, 0.5)) = 0.052
        _NormalInfluence("Normal Map Affects Shadow Shape", Range(0, 1)) = 0.5
        _DetailLight("Normal Detail Lighting", Range(0, 2)) = 0.8

        [Header(Watercolor Shadows)]
        _ShadowColor("Shadow Pigment A", Color) = (0.62, 0.6, 0.86, 1)
        _ShadowColorB("Shadow Pigment B", Color) = (0.8, 0.61, 0.76, 1)
        _ShadowStrength("Pigment Strength", Range(0, 1)) = 0.6
        _ShadowDarkness("Shadow Darkness", Range(0, 0.8)) = 0.15
        _ShadowLightInfluence("Shadow Light Color Influence", Range(0, 1)) = 0.747
        _EdgePooling("Pigment Pooling At Wash Edge", Range(0, 1)) = 1
        _AmbientInfluence("Ambient Influence", Range(0, 1)) = 0.416

        [Header(Brush Strokes)]
        [NoScaleOffset] _BrushAtlas("Brush Atlas (6x6, linear)", 2D) = "gray" {}
        [Enum(Object Triplanar, 0, UV, 1)] _BrushSpace("Brush Projection", Float) = 0
        _BrushScale("Brush Scale (strokes per unit)", Float) = 4
        _BrushStrength("Brush Edge Strength", Range(0, 1.5)) = 0.6
        _BrushDry("Dry Brush Gaps In Shadow", Range(0, 1)) = 0.25
        _BrushPigment("Brush Pigment Variation", Range(0, 1)) = 0.4
        _BrushRandomRotation("Stroke Random Rotation", Range(0, 1)) = 0.35

        [Header(Rim Light)]
        [Enum(Main Light, 0, Custom Light, 1)] _RimLightSource("Rim Light Source", Float) = 0
        _RimColor("Rim Color", Color) = (1, 0.66, 0.66, 1)
        _RimPower("Rim Width (Power)", Range(0.5, 8)) = 6.43
        _RimThreshold("Rim Threshold", Range(0, 1)) = 0.194
        _RimSoftness("Rim Softness", Range(0, 0.5)) = 0
        _RimIntensity("Rim Intensity", Range(0, 3)) = 2.26
        _RimLightInfluence("Rim Light Color Influence", Range(0, 1)) = 1
        _RimShadowMask("Rim Hidden By Cast Shadows", Range(0, 1)) = 1
        [Enum(View Edge Dark Side, 0, Light Band At Shadow Edge, 1, Lit Edge Facing The Light, 2)] _RimMode("Rim Type", Float) = 2
        _RimLightOffset("Light Edge Position (- dark side, + lit side)", Range(-1, 1)) = 0

        [Header(Procedural Noise)]
        _NoiseScale("Wash Noise Scale", Float) = 3
        _NoiseWobble("Wash Edge Irregularity", Range(0, 1)) = 0.152
        _ShadowBoil("Shadow Edge Boil", Range(0, 1)) = 0.274
        _TintNoiseScale("Color Variation Scale", Float) = -0.83
        _GranuleScale("Granulation Scale", Float) = 9
        _Granulation("Shadow Granulation", Range(0, 1)) = 0.021
        _PaperGrain("Paper Grain", Range(0, 0.3)) = 0

        [Header(Color Bleed Edges)]
        _EdgeWidth("Outer Bleed Width (world units)", Range(0, 0.05)) = 0.0023
        _InnerEdgeWidth("Inner Edge Width", Range(0, 0.6)) = 0.392
        _EdgeIntensity("Edge Intensity", Range(0, 1)) = 0.521
        _EdgeSpeed("Boil Speed", Range(0, 10)) = 4.11
        [Toggle] _BoilStepped("Stepped Boil (hand-drawn)", Float) = 1
        _EdgeNoiseScale("Edge Noise Scale", Float) = 498.2
        _EdgeSaturation("Edge Saturation Boost", Range(0, 1.5)) = 0.279
        _EdgeDarkness("Edge Darkness", Range(0, 0.8)) = 0.358
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
        TEXTURE2D(_BrushAtlas);

        // set globally by PainterlyRimLight.cs (not per material)
        float4 _PainterlyRimLightPos;
        float4 _PainterlyRimLightColor;

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _BumpScale;

            half _LightIntensity;
            half _ShadowThreshold;
            half _ShadowSoftness;
            half _NormalInfluence;
            half _DetailLight;
            half _Metallic;
            half _Roughness;

            half4 _ShadowColor;
            half4 _ShadowColorB;
            half _ShadowStrength;
            half _ShadowDarkness;
            half _ShadowLightInfluence;
            half _EdgePooling;
            half _AmbientInfluence;

            half _BrushSpace;
            half _BrushStrength;
            half _BrushPigment;
            half _BrushDry;
            half _BrushRandomRotation;
            float _BrushScale;

            half4 _RimColor;
            half _RimPower;
            half _RimThreshold;
            half _RimSoftness;
            half _RimIntensity;
            half _RimLightInfluence;
            half _RimShadowMask;
            half _RimLightSource;
            half _RimMode;
            half _RimLightOffset;

            float _NoiseScale;
            half _NoiseWobble;
            half _ShadowBoil;
            float _TintNoiseScale;
            float _GranuleScale;
            half _Granulation;
            half _PaperGrain;

            float _EdgeWidth;
            half _InnerEdgeWidth;
            half _EdgeIntensity;
            float _EdgeSpeed;
            half _BoilStepped;
            float _EdgeNoiseScale;
            half _EdgeSaturation;
            half _EdgeDarkness;
        CBUFFER_END

        // ---- procedural noise (object space, no textures, no UV seams)
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
            float v = 0.0, a = 0.5;
            [unroll] for (int k = 0; k < 3; k++)
            {
                v += a * VNoise(p);
                p = p * 2.03 + 17.1;
                a *= 0.5;
            }
            return v / 0.875;
        }

        // "Boiling" noise: a new noise pattern per keyframe (t integer part),
        // cross-faded smoothly or snapped when Stepped Boil is on.
        float3 KeyOffset(float k)
        {
            return float3(Hash13(float3(k, 1.7, 3.1)),
                          Hash13(float3(k, 5.3, 9.2)),
                          Hash13(float3(k, 2.9, 7.7))) * 53.0;
        }

        float FBMT(float3 p, float t)
        {
            float k = floor(t);
            float a = FBM(p + KeyOffset(k));
            if (_BoilStepped > 0.5) return a;
            float b = FBM(p + KeyOffset(k + 1.0));
            return lerp(a, b, smoothstep(0.0, 1.0, frac(t)));
        }

        // ---- brush strokes: stamp random tiles of the 6x6 atlas on a grid.
        // Each grid cell picks a random stroke, mirrors/rotates it, and samples it with
        // gradients taken from the continuous coordinate (no mip seams at cell borders).
        float Stamp(float2 coord, float2 dx, float2 dy, float seed)
        {
            float2 id = floor(coord);
            float2 f = coord - id;
            float h1 = Hash13(float3(id, seed));
            float h2 = Hash13(float3(id, seed + 7.3));
            float h3 = Hash13(float3(id, seed + 13.1));

            float idx = floor(h1 * 36.0);
            float2 tile = float2(fmod(idx, 6.0), floor(idx / 6.0));

            float ang = (h2 - 0.5) * PI * 2.0 * _BrushRandomRotation;
            float cs = cos(ang), sn = sin(ang);
            float2x2 R = float2x2(cs, -sn, sn, cs);
            float2 flip = float2(h3 > 0.5 ? -1.0 : 1.0, frac(h3 * 13.7) > 0.5 ? -1.0 : 1.0);

            float2 c = mul(R, (f - 0.5) * flip) + 0.5;
            float2 gx = mul(R, dx * flip) / 6.0;
            float2 gy = mul(R, dy * flip) / 6.0;
            float2 uv = (tile + saturate(c)) / 6.0;
            return SAMPLE_TEXTURE2D_GRAD(_BrushAtlas, sampler_LinearClamp, uv, gx, gy).r;
        }

        // Two offset layers (second one at a different scale) so the dark gaps between
        // stamps of one layer get covered by strokes of the other.
        float StampLayers(float2 coord, float seed)
        {
            float2 dx = ddx(coord);
            float2 dy = ddy(coord);
            float a = Stamp(coord, dx, dy, seed);
            float b = Stamp(coord * 1.37 + 0.5, dx * 1.37, dy * 1.37, seed + 31.0);
            return max(a, b);
        }

        float BrushMask(float3 p, float3 nOS, float2 uv)
        {
            if (_BrushSpace > 0.5)
                return StampLayers(uv * (_BrushScale * 8.0), 0.0);   // UV mode: stable on animated meshes

            float3 w = pow(abs(nOS) + 1e-4, 4.0);
            w /= (w.x + w.y + w.z);
            float3 ps = p * _BrushScale;
            return StampLayers(ps.yz, 3.0) * w.x
                 + StampLayers(ps.xz, 11.0) * w.y
                 + StampLayers(ps.xy, 23.0) * w.z;
        }

        half3 SampleAlbedo(float2 uv)
        {
            return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).rgb * _BaseColor.rgb;
        }

        // Pigment gathering at edges: more saturated, a bit darker.
        half3 EdgePigment(half3 c)
        {
            half l = dot(c, half3(0.299, 0.587, 0.114));
            return max(lerp(half3(l, l, l), c, 1.0 + _EdgeSaturation), 0.0) * (1.0 - _EdgeDarkness);
        }
        ENDHLSL

        // ------------------------------------------------------------ Forward
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float4 tangentWS  : TEXCOORD3;
                float3 positionOS : TEXCOORD4;
                half   fogFactor  : TEXCOORD5;
                float3 normalOS   : TEXCOORD6;
            };

            // Extra lights use the same noisy wash threshold so they feel painted too.
            float3 AddLight(Light l, float3 N, float3 albedo, float noiseOff)
            {
                float hl = dot(N, l.direction) * 0.5 + 0.5;
                float soft = max(_ShadowSoftness, 0.001);
                float w = smoothstep(_ShadowThreshold - soft, _ShadowThreshold + soft, hl + noiseOff);
                return albedo * l.color * (l.distanceAttenuation * l.shadowAttenuation * w * _LightIntensity);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs vp = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs vn = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS = vp.positionCS;
                o.positionWS = vp.positionWS;
                o.normalOS = v.normalOS;
                o.positionOS = v.positionOS.xyz;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.normalWS = vn.normalWS;
                o.tangentWS = float4(vn.tangentWS, v.tangentOS.w * GetOddNegativeScale());
                o.fogFactor = ComputeFogFactor(vp.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // ---- texture + normal map (original artwork preserved)
                float3 albedo = SampleAlbedo(i.uv);
                float3 diffAlbedo = albedo * (1.0 - _Metallic * 0.85);   // metals keep a little diffuse
                float3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);

                float3 Ng = normalize(i.normalWS);
                float3 T = normalize(i.tangentWS.xyz);
                float3 B = cross(Ng, T) * i.tangentWS.w;
                float3 Nm = normalize(mul(nTS, float3x3(T, B, Ng)));
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);

                // ---- procedural fields
                float3 p = i.positionOS;
                float tt = _Time.y * _EdgeSpeed;
                float n1 = FBM(p * _NoiseScale);
                if (_ShadowBoil > 0.001)
                    n1 = lerp(n1, FBMT(p * _NoiseScale, tt), _ShadowBoil);
                float n2 = FBM(p * _TintNoiseScale + 31.7);
                float gr = VNoise(p * _GranuleScale);
                float en = FBMT(p * _EdgeNoiseScale, tt);     // boiling edge noise
                float brush = (_BrushStrength + _BrushPigment + _BrushDry > 0.001)
                            ? BrushMask(p, i.normalOS, i.uv) : 0.35;
                // white stroke = paint: it pushes the wash boundary outward
                float noiseOff = (n1 - 0.5) * _NoiseWobble - (brush - 0.35) * _BrushStrength;

                // ---- main light
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light ml = GetMainLight(shadowCoord);
                float3 L = ml.direction;

                float3 Nshape = normalize(lerp(Ng, Nm, _NormalInfluence));
                float hl = dot(Nshape, L) * 0.5 + 0.5;
                float soft = max(_ShadowSoftness, 0.001);

                float lightWash = smoothstep(_ShadowThreshold - soft, _ShadowThreshold + soft, hl + noiseOff);
                float castWash = smoothstep(0.15, 0.85, ml.shadowAttenuation + noiseOff * 1.5);
                float wash = min(lightWash, castWash);   // 1 = lit, 0 = shadow
                float s = 1.0 - wash;
                s *= lerp(1.0, smoothstep(0.03, 0.22, brush), _BrushDry);   // dry-brush gaps
                wash = 1.0 - s;
                float edge = 1.0 - abs(wash * 2.0 - 1.0); // peaks along the wash boundary

                // ---- watercolor shadow pigment (multiplies albedo, never replaces it)
                float3 pigment = lerp(_ShadowColor.rgb, _ShadowColorB.rgb, saturate(n2 * 1.4 - 0.2));
                pigment *= lerp(1.0, ml.color, _ShadowLightInfluence);
                float3 sm = lerp(1.0, pigment, _ShadowStrength);
                sm *= 1.0 - _ShadowDarkness;
                sm *= 1.0 - edge * _EdgePooling * 0.3;
                sm = lerp(1.0, sm, lerp(1.0, saturate(brush * 1.8), _BrushPigment));  // thinner wash where stroke is gray
                sm *= 1.0 + (gr - 0.5) * _Granulation;
                float3 amb = SampleSH(Nm);
                sm *= lerp(1.0, saturate(amb * 2.0 + 0.25), _AmbientInfluence);

                float3 litCol = diffAlbedo * ml.color * _LightIntensity;
                float3 shadowCol = diffAlbedo * sm;
                float3 col = lerp(litCol, shadowCol, s);

                // ---- additional lights
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = i.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    half4 shadowMask = half4(1, 1, 1, 1);
                    uint pixelLightCount = GetAdditionalLightsCount();

                    #if USE_FORWARD_PLUS
                    [loop] for (uint fpIndex = 0; fpIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); fpIndex++)
                    {
                        Light l = GetAdditionalLight(fpIndex, i.positionWS, shadowMask);
                        col += AddLight(l, Nshape, diffAlbedo, noiseOff);
                    }
                    #endif

                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light l = GetAdditionalLight(lightIndex, i.positionWS, shadowMask);
                        col += AddLight(l, Nshape, diffAlbedo, noiseOff);
                    LIGHT_LOOP_END
                }
                #endif

                // ---- keep normal-map detail alive in both lit and shadow areas (anti-plastic)
                float detail = dot(Nm, L) - dot(Ng, L);
                col *= clamp(1.0 + detail * _DetailLight * 0.5 * lerp(1.0, 0.5, s), 0.0, 2.0);

                // ---- metallic / roughness: painted GGX highlight + environment reflection
                float pr = max(_Roughness, 0.05);
                float3 specTint = lerp(float3(0.3, 0.3, 0.3), albedo, _Metallic);

                float rough = pr * pr;
                float rough2 = max(rough * rough, 6.1e-5);
                float3 Hv = SafeNormalize(L + V);
                float NoH = saturate(dot(Nm, Hv));
                float LoH = saturate(dot(L, Hv));
                float dd = NoH * NoH * (rough2 - 1.0) + 1.0001;
                float spec = rough2 / (dd * dd * max(0.1, LoH * LoH) * (rough * 4.0 + 2.0));
                spec *= saturate(dot(Nm, L)) * ml.shadowAttenuation * (1.0 - pr);
                spec = 1.0 - exp(-spec * 0.6);
                // threshold broken up by the same noise/brush field = blotchy painted highlight
                float hi = smoothstep(0.35, 0.55, spec - noiseOff * 0.6);
                col += specTint * ml.color * hi * wash;

                float3 R = reflect(-V, Nm);
                float3 env = GlossyEnvironmentReflection(R, i.positionWS, pr, 1.0, GetNormalizedScreenSpaceUV(i.positionCS));
                float fres4 = pow(1.0 - saturate(dot(Nm, V)), 4.0);
                float envAmt = _Metallic + (1.0 - _Metallic) * fres4 * 0.15 * (1.0 - pr);
                col += env * specTint * envAmt;

                // ---- inner color-bleed edge: pigment gathers near the silhouette, boiling over time
                float fres = 1.0 - saturate(dot(Ng, V));
                float e = fres + (en - 0.5) * 0.45;
                float inner = smoothstep(1.0 - _InnerEdgeWidth, 1.0 - _InnerEdgeWidth + 0.2, e);
                float w = saturate(inner * _EdgeIntensity * lerp(0.6, 1.3, en));
                col = lerp(col, EdgePigment(col), w);

                // ---- painterly rim light (boiling, ragged band instead of a smooth gradient)
                // which light drives the rim: the main light, or the Light picked with PainterlyRimLight.cs
                float3 Lr = L;
                float3 Cr = ml.color;
                float rimCast = castWash;
                if (_RimLightSource > 0.5)
                {
                    // w = 0: directional (xyz = direction toward the light), w = 1: point/spot (xyz = position)
                    float3 toLight = _PainterlyRimLightPos.xyz - i.positionWS * _PainterlyRimLightPos.w;
                    Lr = normalize(toLight + 1e-5);
                    Cr = _PainterlyRimLightColor.rgb;
                    rimCast = 1.0;   // the custom light has no shadow map here
                }

                float lf = saturate(dot(Ng, Lr));
                float rimRaw = pow(max(fres, 1e-4), _RimPower) * (1.0 - lf);   // View Edge: depends on the camera
                if (_RimMode > 1.5)
                {
                    // Lit Edge: outline glow, only on the side of the object that faces the light.
                    // "Light Edge Position" sets how far into the lit side it starts.
                    float litSide = smoothstep(_RimLightOffset - 0.1, _RimLightOffset + 0.3, dot(Nshape, Lr));
                    rimRaw = pow(max(fres, 1e-4), _RimPower) * litSide;
                }
                else if (_RimMode > 0.5)
                {
                    // Light Edge: a band around where the surface turns away from the light.
                    // Depends only on the light and the surface (incl. normal map), never on the camera.
                    float band = saturate(1.0 - abs(dot(Nshape, Lr) - _RimLightOffset));
                    rimRaw = pow(band, _RimPower);
                }
                float rsoft = max(_RimSoftness, 0.001);
                float rim = smoothstep(_RimThreshold - rsoft, _RimThreshold + rsoft, rimRaw + (en - 0.5) * 0.25);
                float3 rimCol = lerp(_RimColor.rgb, _RimColor.rgb * Cr, _RimLightInfluence);
                // Hide the rim where another object's shadow covers a surface that faces the light.
                // (Surfaces turned away from the light keep their rim: the shadow map is unreliable there.)
                float facing = smoothstep(0.0, 0.3, dot(Ng, Lr));
                float rimVisible = lerp(1.0, rimCast, facing * _RimShadowMask);
                col += rimCol * rim * _RimIntensity * rimVisible;

                // ---- paper grain (very subtle)
                col *= 1.0 + (VNoise(p * _GranuleScale * 2.7 + 5.0) - 0.5) * _PaperGrain * 2.0;

                col = MixFog(col, i.fogFactor);
                return half4(col, 1);
            }
            ENDHLSL
        }

        // ------------------------------------------------ Outer color bleed
        // Slightly extruded back-face shell with a ragged, boiling noise cutout.
        // Drawn opaque so it sorts correctly with everything else.
        Pass
        {
            Name "ColorBleed"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vertB
            #pragma fragment fragB
            #pragma multi_compile_fog

            struct AttributesB
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct VaryingsB
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionOS : TEXCOORD1;
                float  ext        : TEXCOORD2;
                half   fogFactor  : TEXCOORD3;
            };

            VaryingsB vertB(AttributesB v)
            {
                VaryingsB o;
                float tt = _Time.y * _EdgeSpeed;
                float vn = FBMT(v.positionOS.xyz * _EdgeNoiseScale * 0.6, tt);
                float ext = lerp(0.35, 1.0, saturate(vn * 1.4 - 0.2));   // uneven spread

                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 nWS = TransformObjectToWorldNormal(v.normalOS);
                posWS += nWS * (_EdgeWidth * ext);

                o.positionCS = TransformWorldToHClip(posWS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.positionOS = v.positionOS.xyz;
                o.ext = ext;
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 fragB(VaryingsB i) : SV_Target
            {
                float tt = _Time.y * _EdgeSpeed;
                float n = FBMT(i.positionOS * _EdgeNoiseScale * 3.0 + 9.0, tt);

                // Intensity controls how much of the shell survives; farther-out pixels drop first.
                clip(n - (1.0 - _EdgeIntensity) * 0.85 - (i.ext - 0.35) * 0.3);

                float3 albedo = SampleAlbedo(i.uv);
                float3 c = EdgePigment(albedo * lerp(1.0, _MainLightColor.rgb, 0.5));
                c *= 0.85 + 0.3 * n;   // pigment density variation

                c = MixFog(c, i.fogFactor);
                return half4(c, 1);
            }
            ENDHLSL
        }

        // ------------------------------------------------------- ShadowCaster
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
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
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

            half4 frag(Varyings i) : SV_Target { return 0; }
            ENDHLSL
        }

        // ---------------------------------------------------------- DepthOnly
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

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            half frag(Varyings i) : SV_Target { return i.positionCS.z; }
            ENDHLSL
        }

        // ------------------------------------------------------- DepthNormals
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                #if defined(_GBUFFER_NORMALS_OCT)
                    float3 n = normalize(i.normalWS);
                    float2 oct = PackNormalOctQuadEncode(n);
                    float2 r = saturate(oct * 0.5 + 0.5);
                    return half4(PackFloat2To888(r), 0.0);
                #else
                    return half4(NormalizeNormalPerPixel(i.normalWS), 0.0);
                #endif
            }
            ENDHLSL
        }
    }

    FallBack Off
}
