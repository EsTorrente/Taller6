// Painterly brush strokes + canvas + surface-aligned colour bleed (URP, Unity 6, VR/XR safe).
// Two passes only:
//   0  FlowTensor : tiny (Half/Quarter res) structure tensor, used ONLY to orient strokes + edge darkening
//   1  Composite  : bleed -> brush strokes -> edge darkening -> canvas, one full-res pass
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

        TEXTURE2D_X(_PaintSrc);
        TEXTURE2D_X(_PaintTensor);
        TEXTURE2D(_PaintBrushAtlas);
        TEXTURE2D(_PaintCanvas);

        // Set per draw through a MaterialPropertyBlock (see PainterlyFeature.cs).
        float4 _PaintTexel;       // xy = 1 / size, zw = size of THIS pass' render target
        float4 _PaintFullTexel;   // same, for the full resolution camera target
        float  _DownFactor;       // full-res pixels per tensor pixel

        float  _Intensity;
        float  _StrokeStrength;
        float  _StrokeCellPx;
        float  _StrokeStamp;
        float  _StrokeElong;
        float  _FlowFollow;       // 0 = stroke angles purely random per seed, 1 = follow image edges
        float  _PigmentContrast;
        float  _StrokeEdgeDark;
        float  _HueVar;           // radians
        float  _SatVar;
        float  _ValVar;
        float  _AnimSeed;
        float2 _AtlasGrid;
        float  _AtlasLod;
        float  _Bleed;            // old "ColorBleed" (spread multiplier, 0 = off)
        float  _BleedPx;          // distance of the first tap, full-res pixels
        float2 _BleedRot;         // cos, sin of the bleed angle (old "StrokeAngle")
        float  _EdgeDark;
        float  _EdgeGain;
        float  _CanvasStrength;
        float  _CanvasPx;
        float  _CanvasMid;
        float  _Lite;             // 1 = Quest / low-cost mode (1 stroke layer, 3-tap bleed)
        float  _ShadowAddCount;   // number of additional lights whose shadows are repainted (0..3)
        float  _ShadowPaint;      // 0 = off. How much the real cast shadows are repainted
        float  _ShadowWobblePx;   // how far (full-res px) a brush stroke can push the shadow boundary
        float  _ShadowSoft;       // crispness of the repainted boundary (small = hard painted edge)
        float  _ShadowAmbient;    // fraction of the light that is left inside a shadow (for un-/re-lighting)
        float  _ShadowDarken;
        float  _ShadowEdge;       // pigment pooling along the shadow boundary
        float4 _ShadowTint;

        static const float STROKE_JITTER = 0.08;
        static const float RANDOM_ANISO  = 0.4;    // elongation of strokes where the image has no usable edges
        static const float FLOW_EPS      = 0.002;  // tensor trace at which the image flow gets 50% trust

        struct Attributes
        {
            uint vertexID : SV_VertexID;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv         : TEXCOORD0;
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

        // encoded tensor -> orientation + anisotropy
        void DecodeTensor(float3 t, out float2 dir, out float aniso)
        {
            float dxdx = t.x, dxdy = t.y, dydy = t.z;
            float a = (dxdx + dydy) * 0.5;
            float b = sqrt((dxdx - dydy) * (dxdx - dydy) + 4.0 * (dxdy * dxdy)) * 0.5;
            float l1 = a + b;
            float l2 = a - b;
            float2 ev = float2(l1 - dxdx, -dxdy);
            float el = length(ev);
            dir = el > 1e-8 ? ev / el : float2(0.70710678, 0.70710678);
            float sum = l1 + l2;
            aniso = sum > 1e-8 ? (l1 - l2) / sum : 0.0;
        }

        // PCG hash
        uint Pcg(uint v)
        {
            uint s = v * 747796405u + 2891336453u;
            uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
            return (w >> 22u) ^ w;
        }
        float U01(uint h) { return (h & 0xFFFFFFu) * (1.0 / 16777216.0); }

        float3 HueRotate(float3 c, float a)
        {
            float s, co;
            sincos(a, s, co);
            const float3 k = float3(0.57735027, 0.57735027, 0.57735027);
            return c * co + cross(k, c) * s + k * dot(k, c) * (1.0 - co);
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

            // Reads the full-res camera colour directly (no separate downsample pass).
            // Taps are one tensor-pixel apart, so each bilinear tap already averages a few source pixels.
            float4 FragTensor(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float2 uv = i.uv;
                float2 s = _PaintFullTexel.xy * _DownFactor;

                const float cw = 0.182;
                const float mw = 1.0 - 2.0 * cw;

                float3 tl = S(uv + float2(-s.x,  s.y));
                float3 tc = S(uv + float2(  0.0, s.y));
                float3 tr = S(uv + float2( s.x,  s.y));
                float3 l  = S(uv + float2(-s.x,  0.0));
                float3 r  = S(uv + float2( s.x,  0.0));
                float3 bl = S(uv + float2(-s.x, -s.y));
                float3 bc = S(uv + float2(  0.0,-s.y));
                float3 br = S(uv + float2( s.x, -s.y));

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
            // URP sets these globally; they only select which light / shadow code path is compiled in.
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float SceneShadow(float3 wp)
            {
                return MainLightRealtimeShadow(TransformWorldToShadowCoord(wp));
            }

            float PaintLuma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

            // Adds one light's contribution. w = how much this light matters at this pixel,
            // s0 = its real shadow term, s1 = the same term looked up at the brush-displaced position.
            void AccumLight(float w, float s0, float s1, inout float wT, inout float lo, inout float ln, inout float ed)
            {
                float sP = smoothstep(0.5 - _ShadowSoft, 0.5 + _ShadowSoft, s1);
                float sF = lerp(s0, sP, _ShadowPaint);
                wT += w;
                lo += w * s0;
                ln += w * sF;
                ed += w * 4.0 * sF * (1.0 - sF);
            }

            float DepthLod(float2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_PointClamp, UnityStereoTransformScreenSpaceTex(uv), 0).r;
            }

            // Tensor averaged over the stroke's own footprint (5 taps of a tiny texture). This is what keeps big
            // strokes from twitching: a single-point sample flips direction as soon as anything moves under it.
            float3 TensorOverCell(float2 centerP, float2 res, float cell)
            {
                float2 uv = centerP / res;
                float2 d = (0.25 * cell) / res;
                float3 t = SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv, 0).xyz;
                t += SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv + float2( d.x,  d.y), 0).xyz;
                t += SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv + float2(-d.x,  d.y), 0).xyz;
                t += SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv + float2( d.x, -d.y), 0).xyz;
                t += SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv + float2(-d.x, -d.y), 0).xyz;
                return t * 0.2;
            }

            float3 ApplyStrokeLayer(float3 c, float2 P, float2 res, float2 shift, uint layer, inout float cover, inout float2 sdir)
            {
                float cell = _StrokeCellPx;
                float2 g = (P + shift * cell) / cell;
                int2 cid = (int2)floor(g);

                // The seed only re-rolls WHICH tile / where / which colour each cell gets. Nothing slides.
                uint seed = (uint)_AnimSeed;
                uint h0 = Pcg((uint)cid.x * 1973u ^ Pcg((uint)cid.y * 9277u + layer * 26699u + seed * 6271u + 1u));
                uint h1 = Pcg(h0);
                uint h2 = Pcg(h1);
                uint h3 = Pcg(h2);
                uint h4 = Pcg(h3);

                float2 centerG = cid + 0.5 + (float2(U01(h1), U01(h2)) - 0.5) * STROKE_JITTER;
                float2 l = g - centerG;

                // The stamp can never reach further than stamp/sqrt(2) from its centre -> reject before any fetch.
                if (dot(l, l) > 0.5 * _StrokeStamp * _StrokeStamp) return c;

                // Stroke orientation: image flow where the image has real edges, per-cell random elsewhere.
                // Blended in tensor space so it is continuous (no popping between the two).
                float2 centerP = (centerG - shift) * cell;
                float3 ta = TensorOverCell(centerP, res, cell);
                float trace = ta.x + ta.z;
                float conf = trace / (trace + FLOW_EPS) * _FlowFollow;
                float3 tn = ta / max(trace, 1e-6);

                float2 s2c2;
                sincos(U01(h4) * 6.2831853, s2c2.x, s2c2.y);
                float3 rnd = float3(0.5 + 0.5 * RANDOM_ANISO * s2c2.y,
                                    0.5 * RANDOM_ANISO * s2c2.x,
                                    0.5 - 0.5 * RANDOM_ANISO * s2c2.y);

                float2 dir;
                float an;
                DecodeTensor(lerp(rnd, tn, conf), dir, an);

                float2 r = float2(dot(l, dir), dot(l, float2(-dir.y, dir.x)));
                r.y *= lerp(1.0, _StrokeElong, an);
                if (U01(h3) > 0.5) r.y = -r.y;

                float2 tuv = r / _StrokeStamp + 0.5;
                if (any(tuv < 0.0) || any(tuv > 1.0)) return c;

                float tiles = _AtlasGrid.x * _AtlasGrid.y;
                float tile = min(floor(U01(h0) * tiles), tiles - 1.0);
                float2 tc = float2(fmod(tile, _AtlasGrid.x), floor(tile / _AtlasGrid.x));
                float2 auv = (tc + tuv) / _AtlasGrid;
                float m = SAMPLE_TEXTURE2D_LOD(_PaintBrushAtlas, sampler_LinearClamp, auv, _AtlasLod).r;

                // colour variation hashes only for pixels that are actually covered by a stamp
                uint h5 = Pcg(h4);
                uint h6 = Pcg(h5);
                uint h7 = Pcg(h6);
                float ang = (U01(h5) * 2.0 - 1.0) * _HueVar;
                float sat = 1.0 + (U01(h6) * 2.0 - 1.0) * _SatVar;
                float val = 1.0 + (U01(h7) * 2.0 - 1.0) * _ValVar;

                float3 v = HueRotate(c, ang);
                float luma = dot(v, float3(0.2126, 0.7152, 0.0722));
                v = lerp(float3(luma, luma, luma), v, sat) * val;

                if (m > cover) { cover = m; sdir = dir; }   // reused by the shadow repaint (no extra fetch)

                float edge = 4.0 * m * (1.0 - m);
                v *= (1.0 + (m - 0.5) * _PigmentContrast) * (1.0 - _StrokeEdgeDark * edge);

                return lerp(c, max(v, 0.0), saturate(m * _StrokeStrength * 1.5));
            }

            float3 SrcLin(float2 uv) { return SAMPLE_TEXTURE2D_X_LOD(_PaintSrc, sampler_LinearClamp, uv, 0).rgb; }

            float4 FragComposite(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float2 uv = i.uv;
                float2 res = _PaintTexel.zw;

                // ---- VIEW-RAY DIRECTION ANCHORING (Seamless wrap) ----
                float2 positionNDC = uv * 2.0 - 1.0;
                #if UNITY_UV_STARTS_AT_TOP
                positionNDC.y = -positionNDC.y;
                #endif
                float4 rayW = mul(UNITY_MATRIX_I_VP, float4(positionNDC, 1.0, 1.0));
                float3 viewDir = normalize(rayW.xyz / rayW.w - _WorldSpaceCameraPos);

                // Use continuous sine/cos mapping of angles to eliminate the atan2 seam
                float yaw = atan2(viewDir.x, viewDir.z);
                float pitch = asin(viewDir.y);
                float2 continuousPos = float2(sin(yaw), cos(yaw)) + float2(0, pitch);
                float2 P = continuousPos * res.y;
                // ---------------------------------------------------------------------------------------

                float4 src = LOAD_TEXTURE2D_X(_PaintSrc, int2(i.positionCS.xy));
                float3 c = src.rgb;

                // ---- Colour bleed (the original wet-on-dry multi-tap) ------------------------------------
                float raw = 0.0;
                bool isSky = true;
                float3 wp = float3(0.0, 0.0, 0.0);
                if (_Bleed > 0.0 || _ShadowPaint > 0.0)
                {
                    raw = SampleSceneDepth(uv);
                    wp = ComputeWorldSpacePosition(uv, raw, UNITY_MATRIX_I_VP);
                    #if UNITY_REVERSED_Z
                        isSky = raw < 1e-5;
                    #else
                        isSky = raw > 1.0 - 1e-5;
                    #endif
                }

                if (_Bleed > 0.0)
                {
                    float3 nr = cross(ddy(wp), ddx(wp));
                    float nl2 = dot(nr, nr);

                    [branch]
                    if (!isSky && nl2 > 1e-14)
                    {
                        float3 n = nr * rsqrt(nl2);
                        n = dot(n, wp - _WorldSpaceCameraPos) > 0.0 ? -n : n;

                        float3 up = abs(n.y) > 0.95 ? float3(0, 0, 1) : float3(0, 1, 0);
                        float3 T = normalize(cross(up, n));
                        float3 B = cross(n, T);
                        float3 T2 = T * _BleedRot.x + B * _BleedRot.y;
                        float2 tV = mul((float3x3)UNITY_MATRIX_V, T2).xy;

                        float2 stepUV = tV * (_BleedPx * _Bleed) * _PaintTexel.xy;
                        if (_Lite > 0.5)
                        {
                            float2 o = stepUV * 2.0;
                            c = (c + SrcLin(uv + o) + SrcLin(uv - o)) * (1.0 / 3.0);
                        }
                        else
                        {
                            float3 acc = c;
                            [unroll]
                            for (int k = 1; k <= 3; k++)
                            {
                                float2 o = stepUV * (float)k;
                                acc += SrcLin(uv + o) + SrcLin(uv - o);
                            }
                            c = acc * (1.0 / 7.0);
                        }
                    }
                }

                // ---- Brush strokes -----------------------------------------------------------------------
                float3 cBase = c;
                float cover = -1.0;
                float2 sdir = float2(0.0, 0.0);
                if (_StrokeStrength > 0.0)
                {
                    c = ApplyStrokeLayer(c, P, res, float2(0.0, 0.0), 17u, cover, sdir);
                    if (_Lite < 0.5)
                        c = ApplyStrokeLayer(c, P, res, float2(0.5, 0.5), 41u, cover, sdir);
                }

                // ---- Painterly cast shadows --------------------------------------------------------------
                if (_ShadowPaint > 0.0 && !isSky)
                {
                    float2 uv2 = uv + sdir * (max(cover, 0.0) * _ShadowWobblePx) * _PaintTexel.xy;
                    float raw2 = DepthLod(uv2);
                    float e0 = LinearEyeDepth(raw, _ZBufferParams);
                    float e1 = LinearEyeDepth(raw2, _ZBufferParams);
                    bool sameSurface = abs(e1 - e0) < 0.04 * e0;
                    float3 wp2 = sameSurface ? ComputeWorldSpacePosition(uv2, raw2, UNITY_MATRIX_I_VP) : wp;

                    float wT = 0.0, lo = 0.0, ln = 0.0, ed = 0.0;

                    {
                        float w = PaintLuma(_MainLightColor.rgb);
                        if (w > 1e-4)
                        {
                            float s0 = SceneShadow(wp);
                            float s1 = sameSurface ? SceneShadow(wp2) : s0;
                            AccumLight(w, s0, s1, wT, lo, ln, ed);
                        }
                    }

                    [loop]
                    for (int li = 0; li < (int)_ShadowAddCount; li++)
                    {
                        Light L = GetAdditionalPerObjectLight(li, wp);
                        float w = PaintLuma(L.color) * L.distanceAttenuation;
                        if (w > 1e-4)
                        {
                            float s0 = AdditionalLightRealtimeShadow(li, wp, L.direction);
                            float s1 = sameSurface ? AdditionalLightRealtimeShadow(li, wp2, L.direction) : s0;
                            AccumLight(w, s0, s1, wT, lo, ln, ed);
                        }
                    }

                    if (wT > 1e-4)
                    {
                        float A = _ShadowAmbient;
                        float litOld = lo / wT;
                        float litNew = ln / wT;
                        c *= (A + (1.0 - A) * litNew) / (A + (1.0 - A) * litOld);
                        c *= lerp(float3(1.0, 1.0, 1.0), _ShadowTint.rgb * (1.0 - _ShadowDarken), (1.0 - litNew) * _ShadowPaint);
                        c *= 1.0 - _ShadowEdge * (ed / wT) * _ShadowPaint;
                    }
                }

                // ---- Edge darkening ----------------------------------------------------------------------
                if (_EdgeDark > 0.0)
                {
                    float4 tn = SAMPLE_TEXTURE2D_X_LOD(_PaintTensor, sampler_LinearClamp, uv, 0);
                    float grad = sqrt(max(tn.x + tn.z, 0.0));
                    c *= 1.0 - _EdgeDark * (1.0 - exp(-grad * _EdgeGain));
                }

                // ---- Canvas ------------------------------------------------------------------------------
                if (_CanvasStrength > 0.0)
                {
                    float cv = SAMPLE_TEXTURE2D(_PaintCanvas, sampler_LinearRepeat, P / _CanvasPx).r;
                    c *= lerp(1.0, cv / _CanvasMid, _CanvasStrength);
                }

                return half4(lerp(src.rgb, max(c, 0.0), _Intensity), src.a);
            }
            ENDHLSL
        }
    }
}