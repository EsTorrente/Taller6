// Magic appear / disappear from the Blender "Kid_Magic" and "LightFigure_Magic" materials.
// A linear gradient in the space of a chosen object, mixed with noise, cuts the surface away; a thin band at the
// cut glows purple -> orange with sparkles. The noise is Cycles' own code, so the cut lands where it does in Blender.
// Needs the MAGIC_DISSOLVE_CBUFFER fields (MagicDissolveInput.hlsl) declared before this file.
#ifndef MAGIC_DISSOLVE_INCLUDED
#define MAGIC_DISSOLVE_INCLUDED

uint MagicRot(uint x, uint k) { return (x << k) | (x >> (32u - k)); }

void MagicFinal(inout uint a, inout uint b, inout uint c)
{
    c ^= b; c -= MagicRot(b, 14u);
    a ^= c; a -= MagicRot(c, 11u);
    b ^= a; b -= MagicRot(a, 25u);
    c ^= b; c -= MagicRot(b, 16u);
    a ^= c; a -= MagicRot(c, 4u);
    b ^= a; b -= MagicRot(a, 14u);
    c ^= b; c -= MagicRot(b, 24u);
}

uint MagicHash3(uint3 k)
{
    uint a, b, c;
    a = b = c = 0xdeadbeefu + (3u << 2u) + 13u;
    c += k.z; b += k.y; a += k.x;
    MagicFinal(a, b, c);
    return c;
}

uint MagicHash4(uint4 k)
{
    uint a, b, c;
    a = b = c = 0xdeadbeefu + (4u << 2u) + 13u;
    a += k.x; b += k.y; c += k.z;
    a -= c; a ^= MagicRot(c, 4u); c += b;
    b -= a; b ^= MagicRot(a, 6u); a += c;
    c -= b; c ^= MagicRot(b, 8u); b += a;
    a -= c; a ^= MagicRot(c, 16u); c += b;
    b -= a; b ^= MagicRot(a, 19u); a += c;
    c -= b; c ^= MagicRot(b, 4u); b += a;
    a += k.w;
    MagicFinal(a, b, c);
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

float4 MagicFade(float4 t) { return t * t * t * (t * (t * 6 - 15) + 10); }

float MagicPerlin3(float3 p)
{
    float3 i = floor(p);
    float3 f = p - i;
    uint3 n = (uint3)(int3)i;
    float3 w = MagicFade(float4(f, 0)).xyz;
    float v[8];
    [unroll] for (uint c = 0u; c < 8u; c++)
    {
        uint3 o = uint3(c & 1u, (c >> 1u) & 1u, (c >> 2u) & 1u);
        v[c] = MagicGrad3(MagicHash3(n + o), f - (float3)o);
    }
    return 0.982 * lerp(lerp(lerp(v[0], v[1], w.x), lerp(v[2], v[3], w.x), w.y),
                        lerp(lerp(v[4], v[5], w.x), lerp(v[6], v[7], w.x), w.y), w.z);
}

float MagicPerlin4(float4 p)
{
    float4 i = floor(p);
    float4 f = p - i;
    uint4 n = (uint4)(int4)i;
    float4 w = MagicFade(f);
    float v[16];
    [unroll] for (uint c = 0u; c < 16u; c++)
    {
        uint4 o = uint4(c & 1u, (c >> 1u) & 1u, (c >> 2u) & 1u, (c >> 3u) & 1u);
        v[c] = MagicGrad4(MagicHash4(n + o), f - (float4)o);
    }
    float lo = lerp(lerp(lerp(v[0], v[1], w.x), lerp(v[2], v[3], w.x), w.y),
                    lerp(lerp(v[4], v[5], w.x), lerp(v[6], v[7], w.x), w.y), w.z);
    float hi = lerp(lerp(lerp(v[8], v[9], w.x), lerp(v[10], v[11], w.x), w.y),
                    lerp(lerp(v[12], v[13], w.x), lerp(v[14], v[15], w.x), w.y), w.z);
    return 0.8344 * lerp(lo, hi, w.w);
}

// Blender Noise Texture, FBM, Normalize on (Lacunarity 2). Detail is whole octaves only.
float MagicFbm3(float3 p, float detail, float roughness)
{
    float sum = 0, amp = 1, maxAmp = 0, scale = 1;
    [loop] for (int i = 0; i <= (int)min(detail, 15); i++)
    {
        sum += MagicPerlin3(p * scale) * amp;
        maxAmp += amp;
        amp *= roughness;
        scale *= 2;
    }
    return 0.5 * sum / maxAmp + 0.5;
}

float MagicFbm4(float4 p, float detail, float roughness)
{
    float sum = 0, amp = 1, maxAmp = 0, scale = 1;
    [loop] for (int i = 0; i <= (int)min(detail, 15); i++)
    {
        sum += MagicPerlin4(p * scale) * amp;
        maxAmp += amp;
        amp *= roughness;
        scale *= 2;
    }
    return 0.5 * sum / maxAmp + 0.5;
}

// Blender Mapping node (Point): scale, Euler XYZ rotation, then location
float3 MagicMapping(float3 v)
{
    float3 r = _MagicMapRotation.xyz;
    float ci = cos(r.x), cj = cos(r.y), ch = cos(r.z);
    float si = sin(r.x), sj = sin(r.y), sh = sin(r.z);
    float cc = ci * ch, cs = ci * sh, sc = si * ch, ss = si * sh;
    v *= _MagicMapScale.xyz;
    return float3(cj * ch * v.x + (sj * sc - cs) * v.y + (sj * cc + ss) * v.z,
                  cj * sh * v.x + (sj * ss + cc) * v.y + (sj * cs - sc) * v.z,
                  -sj * v.x + cj * si * v.y + cj * ci * v.z) + _MagicMapLocation.xyz;
}

float MagicEase(float t) { t = saturate(t); return t * t * (3 - 2 * t); }

struct MagicDissolveData
{
    float opacity;  // 1 = surface, 0 = cut away
    float3 glow;    // emission of the band at the cut
};

MagicDissolveData MagicDissolve(float3 positionWS)
{
    MagicDissolveData d;
    d.opacity = 1;
    d.glow = 0;

    // Texture Coordinate > Object of the chosen object (Unity's local x is Blender's -x)
    float3 obj = mul(_MagicWorldToObject, float4(positionWS, 1)).xyz * float3(-1, 1, 1);
    float3 p = MagicMapping(obj) + _MagicMapOffset.xyz;
    float g = saturate(p.x + _MagicGradientOffset);

    // fac = mix(noise colour, gradient). Noise is 0..1, so skip it where the result can't reach the cut or the band.
    float k = _MagicNoiseMix;
    float lowest = g * k, highest = g * k + (1 - k);
    if (highest <= min(_MagicCut.x, _MagicEdge.x)) return d;
    if (lowest >= max(_MagicCut.y, _MagicEdge.z)) { d.opacity = 0; return d; }

    float4 p4 = float4(p, _MagicNoiseW + _MagicNoiseWPerFrame * _MagicFrame) * _MagicNoiseScale;
    // Noise "Color" output, read as a value (luminance): channels offset like Blender's colour noise
    float noise = 0.2126 * MagicFbm4(p4, _MagicNoiseDetail, _MagicNoiseRoughness)
                + 0.7152 * MagicFbm4(p4 + float4(155.580915, 177.154631, 138.140035, 180.185722), _MagicNoiseDetail, _MagicNoiseRoughness)
                + 0.0722 * MagicFbm4(p4 + float4(188.85379, 132.677684, 162.052163, 185.268158), _MagicNoiseDetail, _MagicNoiseRoughness);
    float fac = lerp(noise, g, k);

    d.opacity = saturate((_MagicCut.y - fac) / max(_MagicCut.y - _MagicCut.x, 1e-5));

    // Glow band: Ease ramp 0 -> 1 -> 0 around the cut
    float band = fac < _MagicEdge.y
        ? MagicEase((fac - _MagicEdge.x) / max(_MagicEdge.y - _MagicEdge.x, 1e-5))
        : 1 - MagicEase((fac - _MagicEdge.y) / max(_MagicEdge.z - _MagicEdge.y, 1e-5));
    if (band > 0)
    {
        float colorNoise = MagicFbm3(p * _MagicGlowNoiseScale, _MagicGlowNoiseDetail, 0.5);
        float3 color = lerp(_MagicGlowColorA.rgb, _MagicGlowColorB.rgb,
                            saturate((colorNoise - _MagicGlowColorRamp.x) / max(_MagicGlowColorRamp.y - _MagicGlowColorRamp.x, 1e-5)));
        float4 s4 = float4(p, _MagicSparkleW + _MagicSparkleWPerFrame * _MagicFrame) * _MagicSparkleScale;
        float sparkleNoise = MagicFbm4(s4, _MagicSparkleDetail, 0.5);
        float sparkle = lerp(_MagicSparkleRamp.z, _MagicSparkleRamp.w,
                             saturate((sparkleNoise - _MagicSparkleRamp.x) / max(_MagicSparkleRamp.y - _MagicSparkleRamp.x, 1e-5)));
        d.glow = color * band * sparkle * _MagicGlowStrength;
    }
    return d;
}

// Blender blends this with Alpha Hashed; a per-pixel dither gives the same look on the narrow fade
void MagicClip(MagicDissolveData d, float2 pixel)
{
    float dither = frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
    clip(d.opacity - max(dither, 0.001));
}

#endif
