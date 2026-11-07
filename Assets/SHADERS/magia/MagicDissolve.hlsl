// Magic appear / disappear from the Blender "Kid_Magic" and "LightFigure_Magic" materials.
// A linear gradient in the space of a chosen object, mixed with noise, cuts the surface away; a thin band at the
// cut glows purple -> orange with sparkles. The noise is Cycles' own code, so the cut lands where it does in Blender.
// Needs the MAGIC_DISSOLVE_CBUFFER fields (MagicDissolveInput.hlsl) declared before this file.
//
// OPTIMISED VERSION. Same public API as before (MagicPoint, MagicDissolve, MagicDissolveP, MagicDissolveCheap,
// MagicClip, MagicDissolveData) plus MagicDissolveOpacityP. Output is unchanged unless you define one of the
// optional quality knobs below BEFORE including this file.
//
// Exact optimisations (no visual change):
//  - Hash sharing: the first Jenkins round only depends on b and c, so it is computed once for the two corners that
//    share them (4D noise: both w corners, 3D noise: both x corners) instead of twice.
//  - The glow (colour noise + sparkle noise = the most expensive part) is skipped on pixels that MagicClip is
//    guaranteed to discard anyway (opacity < 0.001), and on passes that don't use it (shadow / depth).
//  - sincos instead of separate sin + cos in the mapping.
// Optional quality knobs (all default to the exact behaviour):
//  - MAGIC_CUT_DETAIL / MAGIC_GLOW_DETAIL / MAGIC_SPARKLE_DETAIL: per-noise octave cap (default MAGIC_MAX_DETAIL).
//  - MAGIC_FAST_NOISE: cut + sparkle noise use 3D Perlin (8 corners) instead of 4D (16 corners), the W animation
//    becomes a drift of the sample point. Same look statistically, not the same pattern as Blender. ~2x cheaper.
#ifndef MAGIC_DISSOLVE_INCLUDED
#define MAGIC_DISSOLVE_INCLUDED

// Max extra octaves for every noise (Blender uses 15). Lower = cheaper; this overrides the material's detail values.
#ifndef MAGIC_MAX_DETAIL
#define MAGIC_MAX_DETAIL 2
#endif
#ifndef MAGIC_CUT_DETAIL
#define MAGIC_CUT_DETAIL MAGIC_MAX_DETAIL
#endif
#ifndef MAGIC_GLOW_DETAIL
#define MAGIC_GLOW_DETAIL MAGIC_MAX_DETAIL
#endif
#ifndef MAGIC_SPARKLE_DETAIL
#define MAGIC_SPARKLE_DETAIL MAGIC_MAX_DETAIL
#endif
#ifndef MAGIC_FAST_DRIFT
#define MAGIC_FAST_DRIFT float3(0.31, 0.19, 0.27) // direction the 3D noise slides along per unit of W (MAGIC_FAST_NOISE)
#endif

uint MagicRot(uint x, uint k)
{
    return (x << k) | (x >> (32u - k));
}

void MagicFinal(inout uint a, inout uint b, inout uint c)
{
    c ^= b;
    c -= MagicRot(b, 14u);
    a ^= c;
    a -= MagicRot(c, 11u);
    b ^= a;
    b -= MagicRot(a, 25u);
    c ^= b;
    c -= MagicRot(b, 16u);
    a ^= c;
    a -= MagicRot(c, 4u);
    b ^= a;
    b -= MagicRot(a, 14u);
    c ^= b;
    c -= MagicRot(b, 24u);
}

// Rounds 2..7 of MagicFinal. Round 1 (c ^= b; c -= rot(b, 14)) doesn't touch a, so callers that hash several
// values differing only in a run it once and share the result.
void MagicFinalAfterR1(inout uint a, inout uint b, inout uint c)
{
    a ^= c;
    a -= MagicRot(c, 11u);
    b ^= a;
    b -= MagicRot(a, 25u);
    c ^= b;
    c -= MagicRot(b, 16u);
    a ^= c;
    a -= MagicRot(c, 4u);
    b ^= a;
    b -= MagicRot(a, 14u);
    c ^= b;
    c -= MagicRot(b, 24u);
}

uint MagicHash3(uint3 k)
{
    uint a, b, c;
    a = b = c = 0xdeadbeefu + (3u << 2u) + 13u;
    c += k.z;
    b += k.y;
    a += k.x;
    MagicFinal(a, b, c);
    return c;
}

// Jenkins hash of 4 inputs split in two: the xyz mixing (plus round 1 of the final mix) is shared by both w corners,
// only the remaining rounds differ
void MagicHash4Pre(uint3 k, out uint a, out uint b, out uint c)
{
    a = b = c = 0xdeadbeefu + (4u << 2u) + 13u;
    a += k.x;
    b += k.y;
    c += k.z;
    a -= c;
    a ^= MagicRot(c, 4u);
    c += b;
    b -= a;
    b ^= MagicRot(a, 6u);
    a += c;
    c -= b;
    c ^= MagicRot(b, 8u);
    b += a;
    a -= c;
    a ^= MagicRot(c, 16u);
    c += b;
    b -= a;
    b ^= MagicRot(a, 19u);
    a += c;
    c -= b;
    c ^= MagicRot(b, 4u);
    b += a;
    // round 1 of MagicFinal (independent of a, so independent of w)
    c ^= b;
    c -= MagicRot(b, 14u);
}

uint MagicHash4Post(uint a, uint b, uint c, uint w)
{
    a += w;
    MagicFinalAfterR1(a, b, c);
    return c;
}

float MagicGrad3(uint h, float3 f)
{
    h &= 15u;
    float u = h < 8u ? f.x : f.y;
    float vt = (h == 12u || h == 14u) ? f.x : f.z;
    float v = h < 4u ? f.y : vt;
    return ((h & 1u) != 0u ? -u : u) + ((h & 2u) != 0u ? -v : v);
}

float MagicGrad4(uint h, float4 f)
{
    h &= 31u;
    float u = h < 24u ? f.x : f.y;
    float v = h < 16u ? f.y : f.z;
    float s = h < 8u ? f.z : f.w;
    return ((h & 1u) != 0u ? -u : u) + ((h & 2u) != 0u ? -v : v) + ((h & 4u) != 0u ? -s : s);
}

float4 MagicFade(float4 t)
{
    return t * t * t * (t * (t * 6 - 15) + 10);
}

float MagicPerlin3(float3 p)
{
    float3 i = floor(p);
    float3 f = p - i;
    uint3 n = (uint3) (int3) i;
    float3 w = MagicFade(float4(f, 0)).xyz;
    const uint seed = 0xdeadbeefu + (3u << 2u) + 13u;
    float v[8];
    // 4 (y, z) pairs; each hashes its two x corners (x, x + 1) sharing round 1 of the final mix
    [unroll]
    for (uint c = 0u; c < 4u; c++)
    {
        uint oy = c & 1u;
        uint oz = c >> 1u;
        uint b = seed + n.y + oy;
        uint cz = seed + n.z + oz;
        cz ^= b;
        cz -= MagicRot(b, 14u);
        uint a0 = seed + n.x;
        uint a1 = a0 + 1u;
        uint b0 = b, c0 = cz, b1 = b, c1 = cz;
        MagicFinalAfterR1(a0, b0, c0);
        MagicFinalAfterR1(a1, b1, c1);
        float3 fo = f - float3(0, oy, oz);
        v[c * 2u] = MagicGrad3(c0, fo);
        v[c * 2u + 1u] = MagicGrad3(c1, fo - float3(1, 0, 0));
    }
    return 0.982 * lerp(lerp(lerp(v[0], v[1], w.x), lerp(v[2], v[3], w.x), w.y),
                        lerp(lerp(v[4], v[5], w.x), lerp(v[6], v[7], w.x), w.y), w.z);
}

float MagicPerlin4(float4 p)
{
    float4 i = floor(p);
    float4 f = p - i;
    uint4 n = (uint4) (int4) i;
    float4 w = MagicFade(f);
    float v[16];
    [unroll]
    for (uint c = 0u; c < 8u; c++)
    {
        uint3 o = uint3(c & 1u, (c >> 1u) & 1u, (c >> 2u) & 1u);
        uint ha, hb, hc;
        MagicHash4Pre(n.xyz + o, ha, hb, hc);
        float3 fo = f.xyz - (float3) o;
        v[c] = MagicGrad4(MagicHash4Post(ha, hb, hc, n.w), float4(fo, f.w));
        v[c + 8u] = MagicGrad4(MagicHash4Post(ha, hb, hc, n.w + 1u), float4(fo, f.w - 1));
    }
    float lo = lerp(lerp(lerp(v[0], v[1], w.x), lerp(v[2], v[3], w.x), w.y),
                    lerp(lerp(v[4], v[5], w.x), lerp(v[6], v[7], w.x), w.y), w.z);
    float hi = lerp(lerp(lerp(v[8], v[9], w.x), lerp(v[10], v[11], w.x), w.y),
                    lerp(lerp(v[12], v[13], w.x), lerp(v[14], v[15], w.x), w.y), w.z);
    return 0.8344 * lerp(lo, hi, w.w);
}

// Blender Noise Texture, FBM, Normalize on (Lacunarity 2). Detail is whole octaves only; `cap` limits the octaves.
float MagicFbm3(float3 p, float detail, float roughness, int cap)
{
    float sum = 0, amp = 1, maxAmp = 0;
    int count = (int) min(detail, (float) cap) + 1;
    [loop]
    for (int i = 0; i < count; i++)
    {
        sum += MagicPerlin3(p) * amp;
        maxAmp += amp;
        amp *= roughness;
        p *= 2;
    }
    return 0.5 * sum / maxAmp + 0.5;
}

float MagicFbm4(float4 p, float detail, float roughness, int cap)
{
    float sum = 0, amp = 1, maxAmp = 0;
    int count = (int) min(detail, (float) cap) + 1;
    [loop]
    for (int i = 0; i < count; i++)
    {
        sum += MagicPerlin4(p) * amp;
        maxAmp += amp;
        amp *= roughness;
        p *= 2;
    }
    return 0.5 * sum / maxAmp + 0.5;
}

// 4D noise of the cut / sparkle. With MAGIC_FAST_NOISE it is a 3D noise whose sample point drifts with W.
float MagicNoiseW(float4 p4, float4 channelOffset, float detail, float roughness, int cap)
{
#if defined(MAGIC_FAST_NOISE)
    float3 q = p4.xyz + channelOffset.xyz + (p4.w + channelOffset.w) * MAGIC_FAST_DRIFT;
    return MagicFbm3(q, detail, roughness, cap);
#else
    return MagicFbm4(p4 + channelOffset, detail, roughness, cap);
#endif
}

// Blender Mapping node (Point): scale, Euler XYZ rotation, then location
float3 MagicMapping(float3 v)
{
    float3 r = _MagicMapRotation.xyz;
    float si, ci, sj, cj, sh, ch;
    sincos(r.x, si, ci);
    sincos(r.y, sj, cj);
    sincos(r.z, sh, ch);
    float cc = ci * ch, cs = ci * sh, sc = si * ch, ss = si * sh;
    v *= _MagicMapScale.xyz;
    return float3(cj * ch * v.x + (sj * sc - cs) * v.y + (sj * cc + ss) * v.z,
                  cj * sh * v.x + (sj * ss + cc) * v.y + (sj * cs - sc) * v.z,
                  -sj * v.x + cj * si * v.y + cj * ci * v.z) + _MagicMapLocation.xyz;
}

float MagicEase(float t)
{
    t = saturate(t);
    return t * t * (3 - 2 * t);
}

struct MagicDissolveData
{
    float opacity; // 1 = surface, 0 = cut away
    float3 glow; // emission of the band at the cut
};

// Affine in world position, so it can be computed per vertex and interpolated exactly (saves trig + matrix per pixel)
float3 MagicPoint(float3 positionWS)
{
    // Texture Coordinate > Object of the chosen object (Unity's local x is Blender's -x)
    float3 obj = mul(_MagicWorldToObject, float4(positionWS, 1)).xyz * float3(-1, 1, 1);
    return MagicMapping(obj) + _MagicMapOffset.xyz;
}

// cheap    : gradient only, no noise (shadow pass)
// wantGlow : false skips the glow band entirely (shadow / depth passes only need the opacity)
MagicDissolveData MagicDissolveCore(float3 p, bool cheap, bool wantGlow)
{
    MagicDissolveData d;
    d.opacity = 1;
    d.glow = 0;

    float g = saturate(p.x + _MagicGradientOffset);

    // fac = mix(noise colour, gradient). Noise is 0..1, so skip it where the result can't reach the cut or the band.
    float k = _MagicNoiseMix;
    float lowest = g * k, highest = g * k + (1 - k);
    if (highest <= min(_MagicCut.x, _MagicEdge.x))
        return d;
    if (lowest >= max(_MagicCut.y, _MagicEdge.z))
    {
        d.opacity = 0;
        return d;
    }

    float noise = 0.5; // cheap mode: gradient only, no noise (shadow pass)
    if (!cheap)
    {
        float4 p4 = float4(p, _MagicNoiseW + _MagicNoiseWPerFrame * _MagicFrame) * _MagicNoiseScale;
#if defined(MAGIC_NOISE_FULL) || !(defined(SHADER_API_MOBILE) || defined(SHADER_API_GLES3) || defined(SHADER_API_VULKAN))
        // Noise "Color" output, read as a value (luminance): channels offset like Blender's colour noise
        noise = 0.2126 * MagicNoiseW(p4, float4(0, 0, 0, 0), _MagicNoiseDetail, _MagicNoiseRoughness, MAGIC_CUT_DETAIL)
              + 0.7152 * MagicNoiseW(p4, float4(155.580915, 177.154631, 138.140035, 180.185722), _MagicNoiseDetail, _MagicNoiseRoughness, MAGIC_CUT_DETAIL)
              + 0.0722 * MagicNoiseW(p4, float4(188.85379, 132.677684, 162.052163, 185.268158), _MagicNoiseDetail, _MagicNoiseRoughness, MAGIC_CUT_DETAIL);
#else
        // Mobile: one channel, contrast rescaled (1 / sqrt(0.2126^2 + 0.7152^2 + 0.0722^2)) to match the spread of the luminance mix
        noise = saturate((MagicNoiseW(p4, float4(0, 0, 0, 0), _MagicNoiseDetail, _MagicNoiseRoughness, MAGIC_CUT_DETAIL) - 0.5) * 1.334 + 0.5);
#endif
    }
    float fac = lerp(noise, g, k);

    d.opacity = saturate((_MagicCut.y - fac) / max(_MagicCut.y - _MagicCut.x, 1e-5));

    // Glow band: Ease ramp 0 -> 1 -> 0 around the cut.
    // Skipped when opacity is below MagicClip's 0.001 floor: such pixels are always discarded, their glow is never seen.
    if (wantGlow && !cheap && d.opacity > 0.001)
    {
        float band = fac < _MagicEdge.y
            ? MagicEase((fac - _MagicEdge.x) / max(_MagicEdge.y - _MagicEdge.x, 1e-5))
            : 1 - MagicEase((fac - _MagicEdge.y) / max(_MagicEdge.z - _MagicEdge.y, 1e-5));
        if (band > 0)
        {
            float colorNoise = MagicFbm3(p * _MagicGlowNoiseScale, _MagicGlowNoiseDetail, 0.5, MAGIC_GLOW_DETAIL);
            float3 color = lerp(_MagicGlowColorA.rgb, _MagicGlowColorB.rgb,
                                saturate((colorNoise - _MagicGlowColorRamp.x) / max(_MagicGlowColorRamp.y - _MagicGlowColorRamp.x, 1e-5)));
            float4 s4 = float4(p, _MagicSparkleW + _MagicSparkleWPerFrame * _MagicFrame) * _MagicSparkleScale;
            float sparkleNoise = MagicNoiseW(s4, float4(0, 0, 0, 0), _MagicSparkleDetail, 0.5, MAGIC_SPARKLE_DETAIL);
            float sparkle = lerp(_MagicSparkleRamp.z, _MagicSparkleRamp.w,
                                 saturate((sparkleNoise - _MagicSparkleRamp.x) / max(_MagicSparkleRamp.y - _MagicSparkleRamp.x, 1e-5)));
            d.glow = color * band * sparkle * _MagicGlowStrength;
        }
    }
    return d;
}

// Forward pass: opacity + glow
MagicDissolveData MagicDissolveP(float3 p)
{
    return MagicDissolveCore(p, false, true);
}
// Shadow pass: gradient only (glow = 0)
MagicDissolveData MagicDissolveCheap(float3 p)
{
    return MagicDissolveCore(p, true, false);
}
// Depth pass: same cut as Forward (noise included) but no glow work (glow = 0)
MagicDissolveData MagicDissolveOpacityP(float3 p)
{
    return MagicDissolveCore(p, false, false);
}

MagicDissolveData MagicDissolve(float3 positionWS)
{
    return MagicDissolveP(MagicPoint(positionWS));
}

// Blender blends this with Alpha Hashed; a per-pixel dither gives the same look on the narrow fade
void MagicClip(MagicDissolveData d, float2 pixel)
{
    float dither = frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
    clip(d.opacity - max(dither, 0.001));
}

#endif
