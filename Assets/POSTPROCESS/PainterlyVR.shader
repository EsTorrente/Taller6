// Watercolour post effect (URP, Unity 6, XR safe). Inspired by the flockaroo / KinoAqua look.
//   Pass 0  FlowTensor : tiny structure tensor -> edge flow direction + colour edge strength
//   Pass 1  Composite  : noise UV distortion -> silhouette bleed -> contour smear -> pigment noise
//                        -> soft tone steps -> edge/crevice pigment pooling -> painted shadows
//                        -> outlines -> paper
// Needs Depth + Normals (requested by PainterlyFeature).
Shader "Hidden/Painterly/BrushCanvas"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        HLSLINCLUDE
        #pragma target 3.5
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

        TEXTURE2D_X(_PaintSrc);
        TEXTURE2D_X(_PaintTensor);
        TEXTURE2D(_PaintCanvas);

        float4 _PaintTexel;      // xy = 1/size, zw = size of this pass' target
        float4 _PaintFullTexel;
        float  _DownFactor;

        // Packed parameters (see PainterlyFeature.cs)
        float4 _P0, _P1, _P2, _P3, _P4, _P5, _P6, _P7, _P8;
        float4 _ShadowTint, _OutlineColor;

        #define K_INTENSITY   _P0.x
        #define K_NOISE_PX    _P0.y
        #define K_WOBBLE_PX   _P0.z
        #define K_TIME        _P0.w
        #define K_SMEAR       _P1.x
        #define K_SMEAR_PX    _P1.y
        #define K_FILL        _P1.z
        #define K_PIGMENT_PX  _P1.w
        #define K_STEP_AMT    _P2.x
        #define K_STEPS       _P2.y
        #define K_STEP_SOFT   _P2.z
        #define K_STEP_NOISE  _P2.w
        #define K_POOL        _P3.x
        #define K_POOL_PX     _P3.y
        #define K_DEPTH_SENS  _P3.z
        #define K_NORMAL_SENS _P3.w
        #define K_COLOR_EDGE  _P4.x
        #define K_EDGE_GAIN   _P4.y
        #define K_CREVICE     _P4.z
        #define K_CREVICE_PX  _P4.w
        #define K_BLEED_PX    _P5.x
        #define K_FEATHER     _P5.y
        #define K_OUTLINE     _P5.z
        #define K_LITE        _P5.w
        #define K_CANVAS      _P6.x
        #define K_CANVAS_PX   _P6.y
        #define K_CANVAS_MID  _P6.z
        #define K_ANCHOR_VIEW _P6.w
        #define K_SH_ADD      _P7.x
        #define K_SH_PAINT    _P7.y
        #define K_SH_WOBBLE   _P7.z
        #define K_SH_SOFT     _P7.w
        #define K_SH_AMBIENT  _P8.x
        #define K_SH_DARKEN   _P8.y
        #define K_SH_EDGE     _P8.z
        #define K_POOL_TINT   _P8.w

        struct Attributes { uint vertexID : SV_VertexID; UNITY_VERTEX_INPUT_INSTANCE_ID };
        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings Vert(Attributes input)
        {
            Varyings o;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
            o.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
            o.uv = GetFullScreenTriangleTexCoord(input.vertexID);
            return o;
        }
        ENDHLSL

        // ------------------------------------------------------------------------------------------------
        Pass
        {
            Name "FlowTensor"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragTensor

            float3 S(float2 uv) { return SAMPLE_TEXTURE2D_X_LOD(_PaintSrc, sampler_LinearClamp, uv, 0).rgb; }

            float4 FragTensor(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float2 uv = i.uv;
                float2 s = _PaintFullTexel.xy * _DownFactor;
                const float cw = 0.182;
                const float mw = 1.0 - 2.0 * cw;

                float3 tl = S(uv + float2(-s.x,  s.y)), tc = S(uv + float2(0.0,  s.y)), tr = S(uv + float2(s.x,  s.y));
                float3 l  = S(uv + float2(-s.x, 0.0)),                                  r  = S(uv + float2(s.x, 0.0));
                float3 bl = S(uv + float2(-s.x, -s.y)), bc = S(uv + float2(0.0, -s.y)), br = S(uv + float2(s.x, -s.y));

                float3 dx = -cw * tl - mw * l - cw * bl + cw * tr + mw * r + cw * br;
                float3 dy =  cw * tl + mw * tc + cw * tr - cw * bl - mw * bc - cw * br;
                return float4(dot(dx, dx), dot(dx, dy), dot(dy, dy), 0.0);
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------------------------------------
        Pass
        {
            Name "Composite"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragComposite
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ---- noise (smooth value noise, no textures needed) -----------------------------------------
            float Hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }
            float VNoise(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(Hash12(i), Hash12(i + float2(1, 0)), u.x),
                            lerp(Hash12(i + float2(0, 1)), Hash12(i + float2(1, 1)), u.x), u.y);
            }
            float FBM(float2 p)
            {
                return (0.5 * VNoise(p) + 0.25 * VNoise(p * 2.03 + 7.1) + 0.125 * VNoise(p * 4.1 + 3.3)) * (1.0 / 0.875);
            }
            // two slowly drifting fields -> a smoothly flowing 2D vector in [-1,1]
            float2 FlowVec(float2 np, float t)
            {
                return float2(FBM(np + float2(t * 0.7, t * 0.3)),
                              FBM(np + float2(31.7 - t * 0.4, 11.3 + t * 0.6))) * 2.0 - 1.0;
            }

            float3 SrcLin(float2 uv) { return SAMPLE_TEXTURE2D_X_LOD(_PaintSrc, sampler_LinearClamp, uv, 0).rgb; }
            float  EyeD(float2 uv) { return LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams); }
            float  Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

            // structure tensor -> direction ALONG edges
            float2 TensorDir(float3 t)
            {
                float a = (t.x + t.z) * 0.5;
                float b = sqrt((t.x - t.z) * (t.x - t.z) + 4.0 * t.y * t.y) * 0.5;
                float2 ev = float2(a + b - t.x, -t.y);
                float el = length(ev);
                return el > 1e-8 ? ev / el : float2(0.7071, 0.7071);
            }

            // ---- painted cast shadows (boundary pushed around by the noise field) -----------------------
            float SceneShadow(float3 wp) { return MainLightRealtimeShadow(TransformWorldToShadowCoord(wp)); }

            void AccumLight(float w, float s0, float s1, inout float wT, inout float lo, inout float ln, inout float ed)
            {
                float sP = smoothstep(0.5 - K_SH_SOFT, 0.5 + K_SH_SOFT, s1);
                float sF = lerp(s0, sP, K_SH_PAINT);
                wT += w; lo += w * s0; ln += w * sF; ed += w * 4.0 * sF * (1.0 - sF);
            }

            float4 FragComposite(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float2 uv = i.uv;
                float2 tx = _PaintTexel.xy;
                float2 res = _PaintTexel.zw;
                float t = K_TIME;

                // ---- noise space: anchored to the view direction (stable in VR) or to the screen ----------
                float2 positionNDC = uv * 2.0 - 1.0;
                #if UNITY_UV_STARTS_AT_TOP
                positionNDC.y = -positionNDC.y;
                #endif
                float4 rayW = mul(UNITY_MATRIX_I_VP, float4(positionNDC, 1.0, 1.0));
                float3 viewDir = normalize(rayW.xyz / rayW.w - _WorldSpaceCameraPos);
                float yaw = atan2(viewDir.x, viewDir.z);
                float2 Pv = (float2(sin(yaw), cos(yaw)) + float2(0, asin(viewDir.y))) * res.y;
                float2 P = lerp(uv * res, Pv, K_ANCHOR_VIEW);

                float2 np = P / K_NOISE_PX;
                float2 nv = FlowVec(np, t);                       // [-1,1], slowly flowing
                float nA = FBM(np * 0.7 + 9.1 + t * 0.2);         // [0,1]

                float4 src = LOAD_TEXTURE2D_X(_PaintSrc, int2(i.positionCS.xy));
                float ign = frac(52.9829189 * frac(dot(i.positionCS.xy, float2(0.06711056, 0.00583715))));

                // ---- Step 2 / 5: edges from depth + normals ----------------------------------------------
                float raw = SampleSceneDepth(uv);
                #if UNITY_REVERSED_Z
                    bool isSky = raw < 1e-5;
                #else
                    bool isSky = raw > 1.0 - 1e-5;
                #endif
                float e0 = LinearEyeDepth(raw, _ZBufferParams);

                float2 o = K_POOL_PX * (0.6 + 0.8 * nA) * tx;     // irregular width
                float2 uR = uv + float2(o.x, 0), uL = uv - float2(o.x, 0), uU = uv + float2(0, o.y), uD = uv - float2(0, o.y);
                float eR = EyeD(uR), eL = EyeD(uL), eU = EyeD(uU), eD = EyeD(uD);
                // second difference: flat or slanted planes cancel, silhouettes and creases do not
                float rel = (abs(eR + eL - 2.0 * e0) + abs(eU + eD - 2.0 * e0)) / max(e0, 1e-3);
                float edgeD = 1.0 - exp(-rel * K_DEPTH_SENS * 15.0);

                float edgeN = 0.0;
                if (!isSky)
                {
                    float3 n0 = SampleSceneNormals(uv);
                    float ns = (1.0 - dot(n0, SampleSceneNormals(uR))) + (1.0 - dot(n0, SampleSceneNormals(uL)))
                             + (1.0 - dot(n0, SampleSceneNormals(uU))) + (1.0 - dot(n0, SampleSceneNormals(uD)));
                    edgeN = 1.0 - exp(-ns * K_NORMAL_SENS * 1.5);
                }
                float edge = saturate(max(edgeD, edgeN));

                // ---- Step 3 + 5: noise UV distortion, extra strong along silhouettes ----------------------
                float2 uvB = uv + nv * (K_WOBBLE_PX + K_BLEED_PX * edge) * tx;
                float3 c = SrcLin(uvB);

                // pigment flow: smear along the image contours (never across them)
                float3 tn = SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv, 0).xyz;
                if (K_SMEAR > 0.0)
                {
                    float2 dir = TensorDir(tn) * K_SMEAR_PX * tx;
                    if (K_LITE > 0.5)
                        c = lerp(c, (c + SrcLin(uvB + dir) + SrcLin(uvB - dir)) * (1.0 / 3.0), K_SMEAR);
                    else
                    {
                        float3 acc = c;
                        [unroll] for (int k = 1; k <= 3; k++) acc += SrcLin(uvB + dir * k) + SrcLin(uvB - dir * k);
                        c = lerp(c, acc * (1.0 / 7.0), K_SMEAR);
                    }
                }
                // silhouette feathering: colour from just across the boundary leaks in
                if (K_FEATHER > 0.0 && edge > 0.01)
                {
                    float3 c1 = SrcLin(uvB - nv * K_BLEED_PX * edge * tx);
                    c = lerp(c, 0.5 * (c + c1), K_FEATHER * edge);
                }

                // ---- Non-uniform fills: damp-paper pigment variation ---------------------------------------
                float pig = FBM(P / K_PIGMENT_PX + float2(t * 0.15, -t * 0.1) + 40.0);
                c *= 1.0 + (pig - 0.5) * 2.0 * K_FILL;

                // ---- Step 4: soft tone steps (in a perceptual space), thresholds roughened by noise ---------
                if (K_STEP_AMT > 0.0)
                {
                    float L = max(Luma(c), 0.0);
                    float x = (sqrt(L) + (pig - 0.5) * K_STEP_NOISE * 2.0) * K_STEPS;
                    float band = floor(x);
                    float s = smoothstep(0.5 - K_STEP_SOFT * 0.5, 0.5 + K_STEP_SOFT * 0.5, x - band);
                    float Lq = max(band + s, 0.0) / K_STEPS;
                    float ratio = clamp((Lq * Lq + 0.002) / (L + 0.002), 0.25, 4.0);
                    c *= lerp(1.0, ratio, K_STEP_AMT);
                }

                // ---- Step 2: crevice darkening (symmetric depth pairs = concave creases only) --------------
                float ao = 0.0;
                if (K_CREVICE > 0.0 && !isSky)
                {
                    int pairs = K_LITE > 0.5 ? 2 : 3;
                    [loop] for (int k = 0; k < pairs; k++)
                    {
                        float a = (k + ign) * (3.14159265 / pairs);
                        float2 off = float2(cos(a), sin(a)) * K_CREVICE_PX * (0.6 + 0.4 * frac(ign * 7.0 + k * 0.37)) * tx;
                        float e1 = EyeD(uv + off), e2 = EyeD(uv - off);
                        float conc = saturate(-(e1 + e2 - 2.0 * e0) / (0.03 * e0));
                        float guard = (abs(e1 - e0) < 0.35 * e0 && abs(e2 - e0) < 0.35 * e0) ? 1.0 : 0.0;
                        ao += conc * guard;
                    }
                    ao = saturate(ao / pairs) * K_CREVICE;
                }

                // ---- Step 2: pigment pooling on edges (darker AND more saturated, like real paint) ---------
                float grad = sqrt(max(tn.x + tn.z, 0.0));
                float colorEdge = (1.0 - exp(-grad * K_EDGE_GAIN)) * K_COLOR_EDGE;
                float pool = saturate(max(max(edge * K_POOL, colorEdge), ao));
                float3 pooled = pow(max(c, 1e-4), 1.0 + K_POOL_TINT) * (1.0 - 0.25 * pool);
                c = lerp(c, pooled, pool);

                // ---- Painted cast shadows ------------------------------------------------------------------
                if (K_SH_PAINT > 0.0 && !isSky)
                {
                    float3 wp = ComputeWorldSpacePosition(uv, raw, UNITY_MATRIX_I_VP);
                    float2 uv2 = uv + nv * K_SH_WOBBLE * tx;
                    float raw2 = SampleSceneDepth(uv2);
                    float e2d = LinearEyeDepth(raw2, _ZBufferParams);
                    bool same = abs(e2d - e0) < 0.04 * e0;
                    float3 wp2 = same ? ComputeWorldSpacePosition(uv2, raw2, UNITY_MATRIX_I_VP) : wp;

                    float wT = 0.0, lo = 0.0, ln = 0.0, ed = 0.0;
                    {
                        float w = Luma(_MainLightColor.rgb);
                        if (w > 1e-4)
                        {
                            float s0 = SceneShadow(wp);
                            AccumLight(w, s0, same ? SceneShadow(wp2) : s0, wT, lo, ln, ed);
                        }
                    }
                    [loop] for (int li = 0; li < (int)K_SH_ADD; li++)
                    {
                        Light L = GetAdditionalPerObjectLight(li, wp);
                        float w = Luma(L.color) * L.distanceAttenuation;
                        if (w > 1e-4)
                        {
                            float s0 = AdditionalLightRealtimeShadow(li, wp, L.direction);
                            AccumLight(w, s0, same ? AdditionalLightRealtimeShadow(li, wp2, L.direction) : s0, wT, lo, ln, ed);
                        }
                    }
                    if (wT > 1e-4)
                    {
                        float A = K_SH_AMBIENT;
                        float litOld = lo / wT, litNew = ln / wT;
                        c *= (A + (1.0 - A) * litNew) / (A + (1.0 - A) * litOld);
                        c *= lerp(float3(1, 1, 1), _ShadowTint.rgb * (1.0 - K_SH_DARKEN), (1.0 - litNew) * K_SH_PAINT);
                        c *= 1.0 - K_SH_EDGE * (ed / wT) * K_SH_PAINT;
                    }
                }

                // ---- Step 6: optional hand-drawn outline ----------------------------------------------------
                if (K_OUTLINE > 0.0)
                {
                    float outl = smoothstep(0.4, 0.7, edge + (pig - 0.5) * 0.4);
                    c = lerp(c, _OutlineColor.rgb, outl * K_OUTLINE);
                }

                // ---- Paper ---------------------------------------------------------------------------------
                if (K_CANVAS > 0.0)
                {
                    float cv = SAMPLE_TEXTURE2D(_PaintCanvas, sampler_LinearRepeat, P / K_CANVAS_PX).r;
                    c *= lerp(1.0, cv / K_CANVAS_MID, K_CANVAS);
                }

                return half4(lerp(src.rgb, max(c, 0.0), K_INTENSITY), src.a);
            }
            ENDHLSL
        }
    }
}
