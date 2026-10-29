// Custom Function for the Disc Shader Graph: Blender's two Noise Textures (FBM, distortion) mixed 0.4.
// Shader Graph only has 2D noise nodes, and the disc needs 3D noise to avoid a seam around the ring.
#ifndef BLACKHOLE_NOISE_INCLUDED
#define BLACKHOLE_NOISE_INCLUDED

float3 bhHash33(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return frac((p.xxy + p.yxx) * p.zyx) * 2 - 1;
}

// Gradient noise. The 1.12 gain matches the spread of Blender's Perlin, which the streak thresholds rely on.
float bhNoise(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    float3 u = f * f * f * (f * (f * 6 - 15) + 10);
    return lerp(lerp(lerp(dot(bhHash33(i), f),
                          dot(bhHash33(i + float3(1, 0, 0)), f - float3(1, 0, 0)), u.x),
                     lerp(dot(bhHash33(i + float3(0, 1, 0)), f - float3(0, 1, 0)),
                          dot(bhHash33(i + float3(1, 1, 0)), f - float3(1, 1, 0)), u.x), u.y),
                lerp(lerp(dot(bhHash33(i + float3(0, 0, 1)), f - float3(0, 0, 1)),
                          dot(bhHash33(i + float3(1, 0, 1)), f - float3(1, 0, 1)), u.x),
                     lerp(dot(bhHash33(i + float3(0, 1, 1)), f - float3(0, 1, 1)),
                          dot(bhHash33(i + float3(1, 1, 1)), f - float3(1, 1, 1)), u.x), u.y), u.z) * 1.12;
}

// ponytail: 5/4 octaves instead of Blender's 14/8 to stay cheap on Quest; raise if the edges look soft.
float bhFbm(float3 p, int octaves, float roughness, float distortion)
{
    p += float3(bhNoise(p + 13.5), bhNoise(p + 41.2), bhNoise(p + 77.9)) * distortion;
    float sum = 0, amp = 1, norm = 0;
    [unroll(5)]
    for (int i = 0; i < octaves; i++)
    {
        sum += bhNoise(p) * amp;
        norm += amp;
        amp *= roughness;
        p *= 2;
    }
    return sum / norm * 0.5 + 0.5;
}

void BlackHoleNoise_float(float3 C, out float N)
{
    N = lerp(bhFbm(C * 3.2, 5, 0.66, 2.6), bhFbm(C * 11, 4, 0.7, 3.5), 0.4);
}

#endif
