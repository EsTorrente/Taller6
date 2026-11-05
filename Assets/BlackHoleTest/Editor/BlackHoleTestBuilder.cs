// Builds the "blackholetest" scene from Gabriel Aguiar's "Unity VFX Graph - Black Hole Effect Tutorial":
// Fresnel + Scroll shader graphs, a sphere VFX graph and a ring VFX graph (two outputs), galaxy skybox, bloom.
// The asmdef is named Unity.VisualEffectGraph.EditorTests because VFX Graph / Shader Graph / URP only open their
// editor internals (needed to create graphs from code) to that assembly name.
// Run: Tools > BlackHoleTest > Build (or it runs once by itself if Temp/build_blackholetest.flag exists).
using System;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEditor.Graphing;
using UnityEditor.Rendering.Universal.ShaderGraph;
using UnityEditor.SceneManagement;
using UnityEditor.ShaderGraph;
using UnityEditor.ShaderGraph.Internal;
using UnityEditor.VFX;
using UnityEditor.VFX.Block;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.VFX;
using UnityEngine.Playables;
using UnityEngine.Timeline;
using Object = UnityEngine.Object;

[InitializeOnLoad]
static class BlackHoleTestBuilder
{
    const string Root = "Assets/BlackHoleTest";
    const string Art = Root + "/Art";
    const string Flag = "Temp/build_blackholetest.flag";
    const float Bright = 1.3f; // disk color boost over the video values (my noise textures are darker than his)
    const string ScenePath = Root + "/blackholetest.unity";

    static BlackHoleTestBuilder()
    {
        if (!File.Exists(Flag)) return;
        var what = File.ReadAllText(Flag).Trim();
        File.Delete(Flag);
        EditorApplication.delayCall += what == "preview" ? RenderPreview : what == "swap" ? Swap : what == "old" ? OldRenders : what == "cam3" ? MoveCamera3 : what == "e3view" ? View3 : what == "impact" ? Impact3 : what == "impactview" ? ImpactView : what == "probe" ? Probe67 : what == "tweak" ? Tweak : what == "buildswap" ? (EditorApplication.CallbackFunction)(() => { Build(); Swap(); }) : Build;
    }

    static void Log(string s) => Debug.Log("[BLACKHOLE] " + s);

    [MenuItem("Tools/BlackHoleTest/Build")]
    static void Build()
    {
        try { BuildInner(); }
        catch (Exception e) { Debug.LogError("[BLACKHOLE] FAILED " + e); }
    }

    static void BuildInner()
    {
        // ---- textures: noise tiles, gradients clamp, alpha from grayscale (the scroll shader uses .A)
        foreach (var n in new[] { "Noise01", "Noise02", "Gradient01", "Gradient02" })
        {
            var ti = (TextureImporter)AssetImporter.GetAtPath($"{Art}/{n}.png");
            ti.alphaSource = TextureImporterAlphaSource.FromGrayScale;
            ti.wrapMode = n.StartsWith("Noise") ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
            ti.SaveAndReimport();
        }
        var rampImp = (TextureImporter)AssetImporter.GetAtPath($"{Art}/DiscRamp.png");
        rampImp.wrapMode = TextureWrapMode.Clamp; rampImp.mipmapEnabled = false; rampImp.SaveAndReimport();
        Texture2D Tex(string n) => AssetDatabase.LoadAssetAtPath<Texture2D>($"{Art}/{n}.png");
        Mesh Ring(string n)
        {
            var mi = (ModelImporter)AssetImporter.GetAtPath($"{Art}/{n}.fbx");
            if (mi.useFileScale) { mi.useFileScale = false; mi.SaveAndReimport(); } // Blender's cm file scale made it 0.07 units wide
            return AssetDatabase.LoadAllAssetsAtPath($"{Art}/{n}.fbx").OfType<Mesh>().First();
        }
        var ringMesh = Ring("Ring01");
        var haloMesh = Ring("Ring02");

        // ---- shader graphs
        Directory.CreateDirectory(Root + "/Shaders");
        var fresnel = MakeFresnelShader(Root + "/Shaders/FresnelShader.shadergraph");
        var scroll = MakeScrollShader(Root + "/Shaders/ScrollShader.shadergraph", Tex("Noise01"), Tex("Gradient01"), Tex("DiscRamp"));
        var distort = MakeDistortionShader(Root + "/Shaders/DistortionShader.shadergraph", Tex("Noise02"), Tex("Gradient01"));
        Log("shader graphs ok");

        // ---- VFX graphs
        Directory.CreateDirectory(Root + "/VFX");
        var tmp = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        var sphereMesh = tmp.GetComponent<MeshFilter>().sharedMesh;
        Object.DestroyImmediate(tmp);

        var sphereVfx = MakeVfx(Root + "/VFX/VFXGraph_BlackHole.vfx", update =>
        {
            var o = MeshOutput(update, fresnel, sphereMesh);
            SetSlot(o, "FresnelPower", 10f);
            o.AddChild(SetAttr("size", 3.5f));
            o.label = "Event Horizon";

            // "Ring02" facing the camera -> the thick glowing halo hugging the sphere. Lives here (not with the disk)
            // so the disk can be scaled per scene without the halo drifting off the sphere.
            var h = MeshOutput(update, scroll, haloMesh);
            SetSlot(h, "NoiseTexture", Tex("Noise01"));
            SetSlot(h, "NoiseTiling", new Vector2(1, 1));
            SetSlot(h, "NoiseSpeed", new Vector2(-0.3f, -0.5f));
            SetSlot(h, "MaskTexture", Tex("Gradient01"));
            SetSlot(h, "ColorRamp", Tex("DiscRamp"));
            h.AddChild(SetAttr("size", 0.5f)); // inner edge (3.5 * 0.5) = sphere radius
            var face = ScriptableObject.CreateInstance<Orient>();
            face.SetSettingValue("mode", Orient.Mode.FaceCameraPosition);
            h.AddChild(face);
            h.label = "Halo (faces camera)";

            var g = update.GetGraph();
            Expose(g, "Rim Color", new Color(96f, 31.04f, 28.8f, 1f), new Vector2(-500, 500), Slot(o, "Color"));
            Expose(g, "Core Color", new Color(0.35f, 0.11f, 0.04f, 1f), new Vector2(-500, 600), Slot(o, "CoreColor"));
            Expose(g, "Halo Color", Color.white * 10f, new Vector2(-500, 700), Slot(h, "Color"));
        });

        // the ring mesh comes in Blender's Z-up, so it stands vertical until rotated 90 on X (as in the video)
        float tilt = ringMesh.bounds.size.y < ringMesh.bounds.size.z ? 0f : 90f;
        var ringVfx = MakeVfx(Root + "/VFX/VFXGraph_Ring.vfx", update =>
        {
            var d = MeshOutput(update, distort, ringMesh);
            SetSlot(d, "NoiseTexture", Tex("Noise02"));
            SetSlot(d, "NoiseTiling", new Vector2(1, 3));
            SetSlot(d, "NoiseSpeed", new Vector2(-0.1f, -0.2f));
            SetSlot(d, "MaskTexture", Tex("Gradient01"));
            RingBlocks(d, tilt);
            d.children.OfType<SetAttribute>().First().inputSlots[0].value = 1.8f; // a bit wider than the disk

            var a = MeshOutput(update, scroll, ringMesh);
            SetSlot(a, "NoiseTexture", Tex("Noise01"));
            SetSlot(a, "NoiseTiling", new Vector2(1, 3));
            SetSlot(a, "NoiseSpeed", new Vector2(-0.15f, -0.3f));
            SetSlot(a, "MaskTexture", Tex("Gradient01"));
            SetSlot(a, "ColorRamp", Tex("DiscRamp"));
            RingBlocks(a, tilt);

            var b = MeshOutput(update, scroll, ringMesh);
            SetSlot(b, "NoiseTexture", Tex("Noise02"));
            SetSlot(b, "NoiseTiling", new Vector2(1, 3));
            SetSlot(b, "NoiseSpeed", new Vector2(-0.1f, -0.2f));
            SetSlot(b, "MaskTexture", Tex("Gradient01"));
            SetSlot(b, "ColorRamp", Tex("DiscRamp"));
            RingBlocks(b, tilt);

            // render order: distortion first (it samples the scene behind), then the additive layers on top
            int order = 0;
            foreach (var o in new VFXContext[] { d, a, b }) ((IVFXSubRenderer)o).vfxSystemSortPriority = order++;
            d.label = "Disk - Heat Distortion"; a.label = "Disk - Main Swirl"; b.label = "Disk - Shards";

            var g = update.GetGraph();
            Expose(g, "Main Swirl Color", Color.white * 11f * Bright, new Vector2(-500, 500), Slot(a, "Color"));
            Expose(g, "Shards Color", Color.white * 3f * Bright, new Vector2(-500, 600), Slot(b, "Color"));
            Expose(g, "Distortion Strength", 0.03f, new Vector2(-500, 700), Slot(d, "Strength"));
        });
        var particlesVfx = MakeParticles(Root + "/VFX/VFXGraph_Particles.vfx");
        Log($"vfx graphs ok (ring tilt {tilt})");

        // ---- skybox: galaxy cubemap already in the project (Vefects), Skybox/Cubemap like the video
        var skyPath = Root + "/Sky_Galaxy.mat";
        var sky = AssetDatabase.LoadAssetAtPath<Material>(skyPath);
        if (!sky) { sky = new Material(Shader.Find("Skybox/Cubemap")); AssetDatabase.CreateAsset(sky, skyPath); }
        sky.SetTexture("_Tex", AssetDatabase.LoadAssetAtPath<Cubemap>(
            "Assets/Vefects/Free Galaxy Shader URP/Galaxy/Textures/T_VFX_Lush_Galaxy_Space_Panorama_Cube_03.hdr"));
        EditorUtility.SetDirty(sky);

        // ---- scene
        // blackholetest itself is regenerated, so only ask about other unsaved scenes
        var active = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
        bool onlyThis = UnityEngine.SceneManagement.SceneManager.sceneCount == 1 && active.path == ScenePath;
        if (!onlyThis && !EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) { Log("cancelled"); return; }
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        RenderSettings.skybox = sky;
        RenderSettings.ambientMode = AmbientMode.Skybox;

        var camGo = new GameObject("Main Camera") { tag = "MainCamera" };
        camGo.transform.SetPositionAndRotation(new Vector3(0, 2.6f, -12f), Quaternion.Euler(9f, 0, 0));
        var cam = camGo.AddComponent<Camera>();
        cam.clearFlags = CameraClearFlags.Skybox; cam.allowHDR = true; cam.farClipPlane = 2000;
        camGo.AddComponent<AudioListener>();
        var camData = camGo.AddComponent<UniversalAdditionalCameraData>();
        camData.renderPostProcessing = true;
        camData.requiresColorOption = CameraOverrideOption.On; // Opaque Texture for the heat distortion

        var vol = new GameObject("Global Volume").AddComponent<Volume>();
        vol.isGlobal = true;
        vol.sharedProfile = MakeProfile(Root + "/BlackHole_Volume.asset");

        new GameObject("VFXGraph_BlackHole").AddComponent<VisualEffect>().visualEffectAsset = sphereVfx;
        new GameObject("VFXGraph_Ring").AddComponent<VisualEffect>().visualEffectAsset = ringVfx;
        new GameObject("VFXGraph_Particles").AddComponent<VisualEffect>().visualEffectAsset = particlesVfx;

        EditorSceneManager.SaveScene(scene, ScenePath);
        AssetDatabase.SaveAssets();
        Log("DONE");
        RenderPreview();
    }

    // bloom makes the HDR fresnel / ring colors glow; ACES keeps them from clipping to flat white
    static VolumeProfile MakeProfile(string path)
    {
        AssetDatabase.DeleteAsset(path);
        var p = ScriptableObject.CreateInstance<VolumeProfile>();
        AssetDatabase.CreateAsset(p, path);
        var bloom = p.Add<Bloom>(true);
        bloom.threshold.Override(1f); bloom.intensity.Override(1.4f); bloom.scatter.Override(0.65f);
        p.Add<Tonemapping>(true).mode.Override(TonemappingMode.ACES);
        foreach (var c in p.components) { c.hideFlags = HideFlags.HideInInspector | HideFlags.HideInHierarchy; AssetDatabase.AddObjectToAsset(c, p); }
        EditorUtility.SetDirty(p);
        return p;
    }

    // ---------------- Shader Graph ----------------
    static GraphData NewUnlitGraph(bool transparent, bool additive = true, bool bothFaces = false)
    {
        var target = (UniversalTarget)Activator.CreateInstance(typeof(UniversalTarget));
        target.TrySetActiveSubTarget(typeof(UniversalUnlitSubTarget));
        if (transparent)
        {
            target.surfaceType = UnityEditor.Rendering.Universal.ShaderGraph.SurfaceType.Transparent;
            target.alphaMode = additive ? UnityEditor.Rendering.Universal.ShaderGraph.AlphaMode.Additive : UnityEditor.Rendering.Universal.ShaderGraph.AlphaMode.Alpha;
        }
        if (bothFaces) target.renderFace = UnityEditor.Rendering.Universal.ShaderGraph.RenderFace.Both;
        typeof(UniversalTarget).GetField("m_SupportVFX", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(target, true);

        var blocks = new[]
        {
            BlockFields.VertexDescription.Position, BlockFields.VertexDescription.Normal, BlockFields.VertexDescription.Tangent,
            BlockFields.SurfaceDescription.BaseColor, BlockFields.SurfaceDescription.Alpha,
        };
        var g = new GraphData();
        g.AddContexts();
        g.InitializeOutputs(new Target[] { target }, blocks);
        g.AddCategory(CategoryData.DefaultCategory());
        g.path = "Shader Graphs";
        return g;
    }

    static System.Random jit = new System.Random(11);
    static Rect At(float x, float y) => new Rect(x + jit.Next(-38, 39), y + jit.Next(-26, 27), 0, 0);

    static T Node<T>(GraphData g, float x, float y) where T : AbstractMaterialNode, new()
    {
        var n = new T();
        n.drawState = new DrawState { position = At(x, y), expanded = true };
        g.AddNode(n);
        return n;
    }

    static PropertyNode Prop(GraphData g, AbstractShaderProperty p, string name, float x, float y)
    {
        p.displayName = name;
        g.AddGraphInput(p);
        var n = new PropertyNode { drawState = new DrawState { position = At(x, y), expanded = true } };
        n.property = p;
        g.AddNode(n);
        return n;
    }

    static void Link(GraphData g, AbstractMaterialNode a, int aSlot, AbstractMaterialNode b, int bSlot) =>
        g.Connect(a.GetSlotReference(aSlot), b.GetSlotReference(bSlot));

    static BlockNode Block(GraphData g, BlockFieldDescriptor d) => g.GetNodes<BlockNode>().First(b => b.descriptor == d);

    static void Group(GraphData g, string title, params AbstractMaterialNode[] nodes)
    {
        var x = nodes.Min(n => n.drawState.position.xMin);
        var y = nodes.Min(n => n.drawState.position.yMin);
        var grp = new GroupData(title, new Vector2(x - 20, y - 60));
        g.CreateGroup(grp);
        foreach (var n in nodes) g.SetGroup(n, grp);
    }

    static void Note(GraphData g, string title, string text, float x, float y) =>
        g.AddStickyNote(new StickyNoteData(title, text, new Rect(x, y, 320, 140)));

    static ShaderGraphVfxAsset Save(GraphData g, string path)
    {
        FileUtilities.WriteShaderGraphToDisk(path, g);
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        var vfx = AssetDatabase.LoadAllAssetsAtPath(path).OfType<ShaderGraphVfxAsset>().FirstOrDefault();
        if (!vfx) throw new Exception("no VFX sub-asset in " + path + " (Support VFX Graph not on?)");
        return vfx;
    }

    // scrolling noise: UV * tiling + speed * time, sampled from the noise texture
    static SampleTexture2DNode ScrollingNoise(GraphData g, Texture2D noiseTex, Vector2 tilingDefault, Vector2 speedDefault, float x, float y)
    {
        var tiling = Prop(g, new Vector2ShaderProperty { value = tilingDefault }, "Noise Tiling", x, y);
        var speed = Prop(g, new Vector2ShaderProperty { value = speedDefault }, "Noise Speed", x - 40, y + 140);
        var time = Node<TimeNode>(g, x - 20, y + 260);
        var speedT = Node<MultiplyNode>(g, x + 220, y + 160);
        Link(g, speed, PropertyNode.OutputSlotId, speedT, 0);
        Link(g, time, TimeNode.OutputSlotId, speedT, 1);
        var uv = Node<TilingAndOffsetNode>(g, x + 440, y + 40);
        Link(g, tiling, PropertyNode.OutputSlotId, uv, 1);
        Link(g, speedT, 2, uv, 2);
        var noiseP = new Texture2DShaderProperty(); noiseP.value.texture = noiseTex;
        var tex = Prop(g, noiseP, "Noise Texture", x + 440, y - 140);
        var sample = Node<SampleTexture2DNode>(g, x + 700, y - 80);
        Link(g, tex, PropertyNode.OutputSlotId, sample, SampleTexture2DNode.TextureInputId);
        Link(g, uv, 3, sample, SampleTexture2DNode.UVInput);
        Group(g, "Scrolling Noise", tiling, speed, time, speedT, uv, tex, sample);
        return sample;
    }

    static SampleTexture2DNode EdgeMask(GraphData g, Texture2D maskTex, float x, float y)
    {
        var maskP = new Texture2DShaderProperty(); maskP.value.texture = maskTex;
        var tex = Prop(g, maskP, "Mask Texture", x, y);
        var sample = Node<SampleTexture2DNode>(g, x + 260, y - 40);
        Link(g, tex, PropertyNode.OutputSlotId, sample, SampleTexture2DNode.TextureInputId);
        Group(g, "Edge Mask (fades along V)", tex, sample);
        return sample;
    }

    // Color(HDR) x Fresnel(power) + Core Color -> Base Color
    static ShaderGraphVfxAsset MakeFresnelShader(string path)
    {
        var g = NewUnlitGraph(false);
        var color = Prop(g, new ColorShaderProperty { colorMode = ColorMode.HDR, value = Color.white }, "Color", -760, -140);
        var power = Prop(g, new Vector1ShaderProperty { value = 1f }, "Fresnel Power", -820, 40);
        var fres = Node<FresnelNode>(g, -560, 20);
        Link(g, power, PropertyNode.OutputSlotId, fres, 2);
        var mul = Node<MultiplyNode>(g, -300, -60);
        Link(g, color, PropertyNode.OutputSlotId, mul, 0);
        Link(g, fres, 3, mul, 1);
        Group(g, "Bright Rim", color, power, fres, mul);

        var core = Prop(g, new ColorShaderProperty { colorMode = ColorMode.HDR, value = Color.black }, "Core Color", -340, 160);
        var add = Node<AddNode>(g, -100, 20);
        Link(g, mul, 2, add, 0);
        Link(g, core, PropertyNode.OutputSlotId, add, 1);
        Group(g, "Core", core, add);
        Link(g, add, 2, Block(g, BlockFields.SurfaceDescription.BaseColor), 0);
        Note(g, "Event horizon", "Rim glow from the fresnel, plus a dim Core Color so the middle is not pitch black. Raise Fresnel Power for a thinner rim.", -820, -340);
        return Save(g, path);
    }

    // noise x mask x Color(HDR) x Color Ramp -> Base Color; noise x mask alpha -> Alpha. Additive, both faces.
    static ShaderGraphVfxAsset MakeScrollShader(string path, Texture2D noiseTex, Texture2D maskTex, Texture2D rampTex)
    {
        var g = NewUnlitGraph(true, bothFaces: true);
        var noise = ScrollingNoise(g, noiseTex, new Vector2(1, 1), new Vector2(1, 0), -1700, -60);
        var mask = EdgeMask(g, maskTex, -1000, 420);

        var mul1 = Node<MultiplyNode>(g, -620, 40);
        Link(g, noise, SampleTexture2DNode.OutputSlotRGBAId, mul1, 0);
        Link(g, mask, SampleTexture2DNode.OutputSlotRGBAId, mul1, 1);
        var color = Prop(g, new ColorShaderProperty { colorMode = ColorMode.HDR, value = Color.white }, "Color", -660, 220);
        var mul2 = Node<MultiplyNode>(g, -420, 100);
        Link(g, mul1, 2, mul2, 0);
        Link(g, color, PropertyNode.OutputSlotId, mul2, 1);
        Group(g, "Intensity", mul1, color, mul2);

        // hue across the disk: ramp sampled along V, nudged by the noise so the color bands wobble
        var meshUV = Node<UVNode>(g, -1000, -460);
        var jitter = Prop(g, new Vector1ShaderProperty { value = 0.12f }, "Hue Jitter", -1000, -320);
        var jitterAmt = Node<MultiplyNode>(g, -760, -360);
        Link(g, noise, SampleTexture2DNode.OutputSlotRId, jitterAmt, 0);
        Link(g, jitter, PropertyNode.OutputSlotId, jitterAmt, 1);
        var rampUV = Node<AddNode>(g, -560, -440);
        Link(g, meshUV, 0, rampUV, 0);
        Link(g, jitterAmt, 2, rampUV, 1);
        var rampP = new Texture2DShaderProperty(); rampP.value.texture = rampTex;
        var ramp = Prop(g, rampP, "Color Ramp", -560, -620);
        var sRamp = Node<SampleTexture2DNode>(g, -340, -540);
        Link(g, ramp, PropertyNode.OutputSlotId, sRamp, SampleTexture2DNode.TextureInputId);
        Link(g, rampUV, 2, sRamp, SampleTexture2DNode.UVInput);
        Group(g, "Color Ramp (outer red to center blue)", meshUV, jitter, jitterAmt, rampUV, ramp, sRamp);

        var tinted = Node<MultiplyNode>(g, -120, -120);
        Link(g, mul2, 2, tinted, 0);
        Link(g, sRamp, SampleTexture2DNode.OutputSlotRGBAId, tinted, 1);
        // Doppler beaming: the side of the ring turning towards the viewer is brighter. Uses the mesh position (not UVs)
        // so the top and bottom faces agree. Brightness = 1 + Beaming * (direction around the ring).x
        var pos = Node<PositionNode>(g, -560, -900);
        typeof(GeometryNode).GetField("m_Space", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(pos, CoordinateSpace.Object);
        var dir = Node<NormalizeNode>(g, -360, -900);
        Link(g, pos, 0, dir, 0);
        var side = Node<SplitNode>(g, -180, -900);
        Link(g, dir, 1, side, SplitNode.InputSlotId);
        var beaming = Prop(g, new Vector1ShaderProperty { value = 0.7f }, "Beaming", -180, -760);
        var beam = Node<MultiplyNode>(g, 20, -860);
        Link(g, side, SplitNode.OutputSlotRId, beam, 0);
        Link(g, beaming, PropertyNode.OutputSlotId, beam, 1);
        var beamOne = Node<AddNode>(g, 200, -860);
        Link(g, beam, 2, beamOne, 0);
        beamOne.FindInputSlot<DynamicVectorMaterialSlot>(1).value = Vector4.one;
        Group(g, "Doppler Beaming (one side brighter)", pos, dir, side, beaming, beam, beamOne);
        var beamed = Node<MultiplyNode>(g, 380, -300);
        Link(g, tinted, 2, beamed, 0);
        Link(g, beamOne, 2, beamed, 1);
        Link(g, beamed, 2, Block(g, BlockFields.SurfaceDescription.BaseColor), 0);
        var split = Node<SplitNode>(g, -200, 160);
        Link(g, mul2, 2, split, SplitNode.InputSlotId);
        Link(g, split, SplitNode.OutputSlotAId, Block(g, BlockFields.SurfaceDescription.Alpha), 0);
        Group(g, "Output", tinted, split);
        Note(g, "Disk / halo layers", "Used by every disk layer and the halo. Noise scrolls along the ring UVs, the mask fades it along V and the ramp adds the hue. Renders both faces so the thickness of the disk shows.", -1700, -620);
        return Save(g, path);
    }

    // the scene behind the disk, sampled at the screen position pushed around by the scrolling noise. Alpha blended,
    // needs the camera's Opaque Texture.
    static ShaderGraphVfxAsset MakeDistortionShader(string path, Texture2D noiseTex, Texture2D maskTex)
    {
        var g = NewUnlitGraph(true, additive: false, bothFaces: true);
        var noise = ScrollingNoise(g, noiseTex, new Vector2(1, 3), new Vector2(-0.1f, -0.2f), -1900, -60);
        var mask = EdgeMask(g, maskTex, -1200, 420);

        var strength = Prop(g, new Vector1ShaderProperty { value = 0.03f }, "Strength", -900, 100);
        var centered = Node<SubtractNode>(g, -860, -120);
        Link(g, noise, SampleTexture2DNode.OutputSlotRId, centered, 0);
        centered.FindInputSlot<DynamicVectorMaterialSlot>(1).value = Vector4.one * 0.5f;
        var off1 = Node<MultiplyNode>(g, -700, -40);
        Link(g, centered, 2, off1, 0);
        Link(g, strength, PropertyNode.OutputSlotId, off1, 1);
        var off2 = Node<MultiplyNode>(g, -500, 40);
        Link(g, off1, 2, off2, 0);
        Link(g, mask, SampleTexture2DNode.OutputSlotRId, off2, 1);
        Group(g, "Offset", centered, strength, off1, off2);

        var screen = Node<ScreenPositionNode>(g, -500, -240);
        var shifted = Node<AddNode>(g, -300, -140);
        Link(g, screen, 0, shifted, 0);
        Link(g, off2, 2, shifted, 1);
        var scene = Node<SceneColorNode>(g, -120, -140);
        Link(g, shifted, 2, scene, SceneColorNode.ScreenPositionSlotId);
        Group(g, "Warped Background", screen, shifted, scene);
        Link(g, scene, SceneColorNode.OutputSlotId, Block(g, BlockFields.SurfaceDescription.BaseColor), 0);
        Link(g, mask, SampleTexture2DNode.OutputSlotRId, Block(g, BlockFields.SurfaceDescription.Alpha), 0);
        Note(g, "Heat distortion", "Bends whatever is behind the disk. Needs Opaque Texture on the camera. Strength around 0.02 to 0.08.", -1900, -420);
        return Save(g, path);
    }

    // ---------------- VFX Graph ----------------
    // single burst of 1 particle, no lifetime (lives forever), manual bounds 100x100x100
    static VisualEffectAsset MakeVfx(string path, Action<VFXBasicUpdate> outputs)
    {
        if (File.Exists(path)) AssetDatabase.DeleteAsset(path);
        var asset = VisualEffectAssetEditorUtility.CreateNewAsset(path);
        var resource = asset.GetOrCreateResource();
        var graph = resource.GetOrCreateGraph();

        var spawner = ScriptableObject.CreateInstance<VFXBasicSpawner>();
        var burst = ScriptableObject.CreateInstance<VFXSpawnerBurst>();
        spawner.AddChild(burst);
        burst.inputSlots.First(s => s.name == "Count").value = 1f;
        var init = ScriptableObject.CreateInstance<VFXBasicInitialize>();
        var update = ScriptableObject.CreateInstance<VFXBasicUpdate>();
        graph.AddChild(spawner); graph.AddChild(init); graph.AddChild(update);
        spawner.position = new Vector2(-34, -430); init.position = new Vector2(12, -170); update.position = new Vector2(-6, 140);
        spawner.LinkTo(init);
        init.LinkTo(update);
        spawner.label = "Spawn Once"; init.label = "One Particle, Lives Forever"; update.label = "No Movement";

        var data = init.GetData();
        data.SetSettingValue("capacity", 1u);
        data.SetSettingValue("boundsMode", BoundsSettingMode.Manual);
        init.inputSlots.First(s => s.name == "bounds").value = new AABox { center = Vector3.zero, size = Vector3.one * 100f };

        outputs(update);
        resource.WriteAssetWithSubAssets();
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        return AssetDatabase.LoadAssetAtPath<VisualEffectAsset>(path);
    }

    // glowing specks scattered over the disk, drifting around the hole and fading in/out
    static VisualEffectAsset MakeParticles(string path)
    {
        if (File.Exists(path)) AssetDatabase.DeleteAsset(path);
        var asset = VisualEffectAssetEditorUtility.CreateNewAsset(path);
        var resource = asset.GetOrCreateResource();
        var graph = resource.GetOrCreateGraph();

        var spawner = ScriptableObject.CreateInstance<VFXBasicSpawner>();
        var rate = ScriptableObject.CreateInstance<VFXSpawnerConstantRate>();
        spawner.AddChild(rate);
        rate.inputSlots.First(s => s.name == "Rate").value = 90f;
        var init = ScriptableObject.CreateInstance<VFXBasicInitialize>();
        var update = ScriptableObject.CreateInstance<VFXBasicUpdate>();
        var output = ScriptableObject.CreateInstance<VFXPlanarPrimitiveOutput>();
        graph.AddChild(spawner); graph.AddChild(init); graph.AddChild(update); graph.AddChild(output);
        spawner.position = new Vector2(-22, -560); init.position = new Vector2(8, -290); update.position = new Vector2(-15, 230); output.position = new Vector2(26, 520);
        spawner.LinkTo(init); init.LinkTo(update); update.LinkTo(output);

        var data = init.GetData();
        data.SetSettingValue("capacity", 512u);
        data.SetSettingValue("boundsMode", BoundsSettingMode.Manual);
        init.inputSlots.First(s => s.name == "bounds").value = new AABox { center = Vector3.zero, size = Vector3.one * 100f };

        // ring of the disk (flat on XZ), from ~0.25 to 1 x 9 units
        var pos = ScriptableObject.CreateInstance<PositionShape>();
        pos.SetSettingValue("shape", PositionShapeBase.Type.Circle);
        pos.SetSettingValue("positionMode", PositionBase.PositionMode.ThicknessRelative);
        init.AddChild(pos);
        var arc = TArcCircle.defaultValue;
        arc.circle.radius = 9f;
        arc.circle.transform.angles = new Vector3(90, 0, 0);
        SetSlot(pos, "arcCircle", arc);
        SetSlot(pos, "Thickness", 0.75f);

        init.AddChild(SetAttrRandom("lifetime", 5f, 11f));
        init.AddChild(SetAttrRandom("size", 0.012f, 0.045f));
        init.AddChild(SetAttrRandom("color", new Vector3(6f, 5.2f, 4.6f), new Vector3(8f, 3.2f, 1.2f)));

        // every frame: velocity along the orbit (overwrite), then a pull towards the center (add) -> they spiral in
        var orbit = ScriptableObject.CreateInstance<VelocityTangent>();
        orbit.SetSettingValue("composition", AttributeCompositionMode.Overwrite);
        update.AddChild(orbit);
        SetSlot(orbit, "axis", new Line { start = Vector3.zero, end = Vector3.up });
        SetSlot(orbit, "Speed", 1.3f);
        var fall = ScriptableObject.CreateInstance<VelocitySpherical>();
        fall.SetSettingValue("composition", AttributeCompositionMode.Add);
        update.AddChild(fall);
        SetSlot(fall, "center", Vector3.zero);
        SetSlot(fall, "Speed", -0.9f);
        var turb = ScriptableObject.CreateInstance<Turbulence>();
        update.AddChild(turb);
        SetSlot(turb, "Intensity", 0.1f);

        output.SetSettingValue("blendMode", VFXAbstractRenderedOutput.BlendMode.Additive);
        var fade = ScriptableObject.CreateInstance<AttributeFromCurve>();
        fade.SetSettingValue("attribute", "alpha");
        output.AddChild(fade);
        fade.inputSlots[0].value = new AnimationCurve(new Keyframe(0, 0), new Keyframe(0.2f, 1), new Keyframe(0.8f, 1), new Keyframe(1, 0));

        spawner.label = "Steady Stream"; init.label = "Spawn on the Disk"; update.label = "Orbit and Fall In"; output.label = "Sparks";
        resource.WriteAssetWithSubAssets();
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        return AssetDatabase.LoadAssetAtPath<VisualEffectAsset>(path);
    }

    static VFXBlock SetAttrRandom(string attribute, object a, object b)
    {
        var blk = ScriptableObject.CreateInstance<SetAttribute>();
        blk.SetSettingValue("attribute", attribute);
        blk.SetSettingValue("Random", RandomMode.Uniform);
        blk.inputSlots[0].value = a;
        blk.inputSlots[1].value = b;
        return blk;
    }

    static VFXComposedParticleOutput MeshOutput(VFXBasicUpdate update, ShaderGraphVfxAsset sg, Mesh mesh)
    {
        var graph = update.GetGraph();
        var o = ScriptableObject.CreateInstance<VFXComposedParticleOutput>();
        o.SetSettingValue("m_Topology", new ParticleTopologyMesh());
        o.SetSettingValue("shaderGraph", sg);
        graph.AddChild(o);
        int idx = graph.children.OfType<VFXComposedParticleOutput>().Count() - 1;
        o.position = new Vector2(470 * idx - 120 + jit.Next(-40, 41), 440 + (idx % 2) * 35 + jit.Next(-20, 21));
        update.LinkTo(o);
        o.inputSlots.First(s => s.property.type == typeof(Mesh)).value = mesh;
        return o;
    }

    static void RingBlocks(VFXContext o, float tilt)
    {
        o.AddChild(SetAttr("size", 1.5f));
        o.AddChild(SetAttr("angle", new Vector3(tilt, 0, 0)));
        o.AddChild(SetAttr("scale", new Vector3(1, 1, 0.25f))); // thin disk: top and bottom faces close together
    }

    static VFXBlock SetAttr(string attribute, object value)
    {
        var b = ScriptableObject.CreateInstance<SetAttribute>();
        b.SetSettingValue("attribute", attribute);
        b.inputSlots[0].value = value;
        return b;
    }

    // exposed property on the Blackboard, linked to slots -> overridable per scene on the Visual Effect component
    static void Expose(VFXGraph g, string name, object value, Vector2 pos, params VFXSlot[] targets)
    {
        var p = ScriptableObject.CreateInstance<VFXParameter>();
        p.Init(value.GetType());
        p.SetSettingValue("m_ExposedName", name);
        p.SetSettingValue("m_Exposed", true);
        g.AddChild(p);
        p.value = value;
        foreach (var t in targets) p.outputSlots[0].Link(t);
        p.CreateDefaultNode(pos + new Vector2(jit.Next(-60, 61), jit.Next(-25, 26)));
    }

    static VFXSlot Slot(VFXContext o, string name)
    {
        string K(string s) => s.Replace("_", "").Replace(" ", "").ToLowerInvariant();
        return o.inputSlots.First(s => K(s.name) == K(name));
    }

    // VFX names shader graph slots by reference name (e.g. "_Noise_Speed"); match ignoring case / underscores / spaces
    static void SetSlot(IVFXSlotContainer o, string name, object value)
    {
        string K(string s) => s.Replace("_", "").Replace(" ", "").ToLowerInvariant();
        var slot = o.inputSlots.FirstOrDefault(s => K(s.name) == K(name));
        if (slot == null) throw new Exception($"slot {name} not found, have: {string.Join(", ", o.inputSlots.Select(s => s.name))}");
        slot.value = value;
    }

    // ---------------- swap into ESCENA3 / ESCENA67 ----------------
    static readonly string[] SwapScenes = { "ESCENA3", "ESCENA67" };
    static class Tune { public static float rim = 0.5f, core = 0.08f, halo = 4f, main = 15f, shards = 4f, distortion = 0.02f; } // x1.5 in ESCENA3, x3 in ESCENA67
    static int swapIndex;

    static void Swap()
    {
        swapIndex = 0;
        SwapNext();
    }

    static void SwapNext()
    {
        if (swapIndex >= SwapScenes.Length) { Log("SWAP DONE"); return; }
        var name = SwapScenes[swapIndex++];
        try { SwapScene(name); }
        catch (Exception e) { Debug.LogError("[BLACKHOLE] SWAP FAILED " + name + " " + e); SwapNext(); }
    }

    static (Vector3 center, float radius, Vector3 normal) Measure(SkinnedMeshRenderer smr)
    {
        var m = new Mesh();
        smr.BakeMesh(m);
        var t = smr.transform;
        var mat = Matrix4x4.TRS(t.position, t.rotation, Vector3.one);
        var pts = m.vertices.Select(v => mat.MultiplyPoint3x4(v)).ToArray();
        var c = pts.Aggregate(Vector3.zero, (a, b) => a + b) / pts.Length;
        var r = pts.Max(p => (p - c).magnitude);
        var ns = m.normals.Select(v => mat.MultiplyVector(v).normalized).ToArray();
        var n0 = ns[0];
        var n = ns.Aggregate(Vector3.zero, (a, b) => a + (Vector3.Dot(a.sqrMagnitude > 0 ? a : n0, b) < 0 ? -b : b)).normalized;
        Object.DestroyImmediate(m);
        return (c, r, n);
    }

    static void SwapScene(string sceneName)
    {
        var path = $"Assets/Scenes/ESCENAS/{sceneName}.unity";
        var scene = EditorSceneManager.OpenScene(path, OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == sceneName);
        var fbxRoot = root.transform.Find(sceneName + "_ROOT");
        var bone = fbxRoot.Find("Armature/Bone");
        var sphere = fbxRoot.Find("BH_02").GetComponent<SkinnedMeshRenderer>();
        var reflection = fbxRoot.Find("BH_Reflection").GetComponent<SkinnedMeshRenderer>();
        var disc = fbxRoot.Find("Disc").GetComponent<SkinnedMeshRenderer>();
        // pose straight from the FBX animation clip (scrubbing the Timeline in edit mode does not move the bone in every scene)
        var fbxPath = AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar);
        var clip = AssetDatabase.LoadAllAssetsAtPath(fbxPath).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        void Pose(double t) => clip.SampleAnimation(root, (float)t);

        // remember the saved pose; scrubbing the timeline below moves things
        var saved = root.GetComponentsInChildren<UnityEngine.Transform>(true).Select(t => (t, t.localPosition, t.localRotation, t.localScale)).ToArray();
        void Restore() { foreach (var (t, p, r, s) in saved) { if (!t) continue; t.localPosition = p; t.localRotation = r; t.localScale = s; } }

        // find when the old black hole is biggest and measure it there
        double bestT = 0; float bestR = 0;
        for (int i = 0; i <= 120; i++)
        {
            double t = clip.length * i / 120.0;
            Pose(t);
            var r = Measure(sphere).radius;
            if (r > bestR) { bestR = r; bestT = t; }
        }
        // measure once it has settled (near the end of the clip); ESCENA67 overshoots while it pops in
        Pose(clip.length * 0.98);
        if (Measure(sphere).radius > bestR * 0.5f) bestT = clip.length * 0.98;
        Pose(bestT);
        var sph = Measure(sphere);
        var dsk = Measure(disc);
        if (dsk.normal.y < 0) dsk.normal = -dsk.normal; // same side up in every scene, so the swirl turns the same way
        Log($"{sceneName}: biggest at t={bestT:0.0}s sphere r={sph.radius:0.00} disc r={dsk.radius:0.00} normal={dsk.normal} bone scale={bone.lossyScale}");

        // new black hole under the bone so it follows the animation; sized so the new sphere = the old sphere
        var old = bone.Find("BlackHole_VFX");
        if (old) Object.DestroyImmediate(old.gameObject);
        var bh = new GameObject("BlackHole_VFX").transform;
        bh.SetParent(bone, false);
        float f = sph.radius / 1.75f;                           // our sphere is 1.75 units in radius
        float sgn = Mathf.Sign(bone.lossyScale.x);              // the bone is scaled -70, cancel the flip
        bh.localScale = Vector3.one * (f / Mathf.Abs(bone.lossyScale.x)) * sgn;
        bh.position = sph.center;
        bh.rotation = Quaternion.FromToRotation(Vector3.up, dsk.normal);
        Log($"{sceneName}: BlackHole_VFX lossyScale={bh.lossyScale} up.normal={Vector3.Dot(bh.up, dsk.normal):0.000} local={bh.localPosition} {bh.localEulerAngles} {bh.localScale}");
        VisualEffect Add(string n, float scale)
        {
            var go = new GameObject(n.Replace("VFXGraph_", ""));
            go.transform.SetParent(bh, false);
            go.transform.localScale = Vector3.one * scale;
            var v = go.AddComponent<VisualEffect>();
            v.visualEffectAsset = AssetDatabase.LoadAssetAtPath<VisualEffectAsset>($"{Root}/VFX/{n}.vfx");
            return v;
        }
        // the disk is scaled down to the old disk's size; sphere + halo keep matching the old sphere
        float diskScale = dsk.radius / (10.5f * f);
        var core = Add("VFXGraph_BlackHole", 1f);
        var ring = Add("VFXGraph_Ring", diskScale);
        Add("VFXGraph_Particles", diskScale);
        // per-scene look: these scenes see it from very close, so it is toned down from the test scene
        if (sceneName == "ESCENA3")
        {
            core.SetVector4("Rim Color", new Vector4(200f, 170f, 140f, 1f));
            core.SetVector4("Core Color", new Vector4(0f, 0f, 0f, 1f));
            core.SetVector4("Halo Color", Vector4.one * 14f);
            ring.SetVector4("Main Swirl Color", Vector4.one * 22.5f);
            ring.SetVector4("Shards Color", Vector4.one * 6f);
        }
        else
        {
            core.SetVector4("Rim Color", new Vector4(144f, 46.56f, 43.2f, 1.5f));
            core.SetVector4("Core Color", new Vector4(0.028f, 0.0088f, 0.0032f, 0.08f));
            core.SetVector4("Halo Color", Vector4.one * 12f);
            ring.SetVector4("Main Swirl Color", Vector4.one * 45f);
            ring.SetVector4("Shards Color", Vector4.one * 12f);
        }
        ring.SetFloat("Distortion Strength", 0.02f);
        EditorUtility.SetDirty(core); EditorUtility.SetDirty(ring);
        Log($"{sceneName}: diskScale={diskScale:0.000}");

        // hide the old one
        sphere.enabled = false; reflection.enabled = false; disc.enabled = true; // old disk stays as an extra layer: its displacement gives volume
        foreach (var mb in root.GetComponentsInChildren<MonoBehaviour>(true).Where(m => m.GetType().Name == "BlackHoleParticles")) mb.enabled = false;

        // the heat distortion samples the Opaque Texture
        foreach (var cam in Object.FindObjectsByType<Camera>(FindObjectsInactive.Include))
        {
            if (!cam.TryGetComponent<UniversalAdditionalCameraData>(out var data)) data = cam.gameObject.AddComponent<UniversalAdditionalCameraData>();
            data.requiresColorOption = CameraOverrideOption.On;
            EditorUtility.SetDirty(data);
            if (!cam.GetComponentInParent<Unity.XR.CoreUtils.XROrigin>(true) && cam.enabled)
            {
                cam.enabled = false;
                if (cam.TryGetComponent<AudioListener>(out var ear)) ear.enabled = false;
                Log($"{sceneName}: turned off stray camera {cam.name}");
            }
        }

        Restore();
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);
        Log($"{sceneName}: saved");

        // render from the scene's own camera at the biggest moment
        var view = Object.FindObjectsByType<Camera>(FindObjectsInactive.Include).Where(c => c.gameObject.activeInHierarchy)
            .OrderByDescending(c => c.enabled).First();
        Pose(bestT);
        // plus a fixed outside view (a bit above the disk, 4 sphere radii back) so both scenes compare the same way
        var eye = new GameObject("_eye").transform;
        eye.position = sph.center + dsk.normal * sph.radius * 0.6f + Vector3.Cross(dsk.normal, Vector3.right).normalized * sph.radius * 4.5f;
        eye.LookAt(sph.center, dsk.normal);
        var eyeCam = eye.gameObject.AddComponent<Camera>(); eyeCam.enabled = false;
        RenderFrom(view, $"Logs/swap_{sceneName}.png", () =>
            RenderFrom(eyeCam, $"Logs/outside_{sceneName}.png", () => { Object.DestroyImmediate(eye.gameObject); Restore(); SwapNext(); }));
    }

    // same cameras / moments, but with the original black hole showing (scene is not saved)
    static void OldRenders() { swapIndex = 0; OldNext(); }
    static void OldNext()
    {
        if (swapIndex >= SwapScenes.Length) { Log("OLD DONE"); return; }
        var sceneName = SwapScenes[swapIndex++];
        var scene = EditorSceneManager.OpenScene($"Assets/Scenes/ESCENAS/{sceneName}.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == sceneName);
        var fbxRoot = root.transform.Find(sceneName + "_ROOT");
        foreach (var n in new[] { "BH_02", "BH_Reflection", "Disc" }) fbxRoot.Find(n).GetComponent<SkinnedMeshRenderer>().enabled = true;
        fbxRoot.Find("Armature/Bone/BlackHole_VFX").gameObject.SetActive(false);
        var clip = AssetDatabase.LoadAllAssetsAtPath(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        clip.SampleAnimation(root, clip.length * (sceneName == "ESCENA3" ? 12.7f / clip.length : 0.98f));
        var view = Object.FindObjectsByType<Camera>(FindObjectsInactive.Include).Where(c => c.gameObject.activeInHierarchy).OrderByDescending(c => c.enabled).First();
        RenderFrom(view, $"Logs/old_{sceneName}.png", OldNext);
    }

    static void Probe67()
    {
        var scene = EditorSceneManager.OpenScene("Assets/Scenes/ESCENAS/ESCENA67.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == "ESCENA67");
        var clip = AssetDatabase.LoadAllAssetsAtPath(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        var bh = root.transform.Find("ESCENA67_ROOT/Armature/Bone/BlackHole_VFX");
        var cams = Object.FindObjectsByType<Camera>(FindObjectsInactive.Include);
        foreach (var t in new[] { 57.5f, 60f, 65f, 70.5f })
        {
            clip.SampleAnimation(root, t);
            Log($"t={t} bh={bh.position} scale={bh.lossyScale.x:0.0} cams=" + string.Join(" | ", cams.Select(c => $"{c.name}(en={c.enabled},act={c.gameObject.activeInHierarchy}) {c.transform.position} fwd={c.transform.forward}")));
        }
        foreach (var r in root.GetComponentsInChildren<Renderer>(true).Where(r => r.enabled && r.gameObject.activeInHierarchy && r.bounds.size.magnitude > 200))
            Log($"big renderer {r.name} bounds={r.bounds.center} size={r.bounds.size} queue={r.sharedMaterial?.renderQueue} shader={r.sharedMaterial?.shader.name}");
        Log("PROBE DONE");
    }

    // ESCENA3: viewpoint above the disk and further back, same side of the black hole, kept level for VR
    static void MoveCamera3()
    {
        var scene = EditorSceneManager.OpenScene("Assets/Scenes/ESCENAS/ESCENA3.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == "ESCENA3");
        var fbxRoot = root.transform.Find("ESCENA3_ROOT");
        var unityCam = fbxRoot.Find("UnityCamera");
        var clip = AssetDatabase.LoadAllAssetsAtPath(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        var saved = root.GetComponentsInChildren<UnityEngine.Transform>(true).Select(t => (t, t.localPosition, t.localRotation, t.localScale)).ToArray();
        void Restore() { foreach (var (t, p, r, s) in saved) { if (!t) continue; t.localPosition = p; t.localRotation = r; t.localScale = s; } }

        // put UnityCamera back to its original pose from the FBX; the rig gets its own ViewPoint instead
        var src = AssetDatabase.LoadAssetAtPath<GameObject>(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).transform.Find("ESCENA3_ROOT/UnityCamera");
        unityCam.localPosition = src.localPosition; unityCam.localRotation = src.localRotation;
        saved = root.GetComponentsInChildren<UnityEngine.Transform>(true).Select(t => (t, t.localPosition, t.localRotation, t.localScale)).ToArray();
        clip.SampleAnimation(root, 12.7f);
        var sph = Measure(fbxRoot.Find("BH_02").GetComponent<SkinnedMeshRenderer>());
        var dsk = Measure(fbxRoot.Find("Disc").GetComponent<SkinnedMeshRenderer>());
        if (dsk.normal.y < 0) dsk.normal = -dsk.normal;
        var from = unityCam.position - sph.center;
        var flat = Vector3.ProjectOnPlane(from, dsk.normal).normalized;
        float dist = from.magnitude * 1.8f, elev = 30f * Mathf.Deg2Rad;
        var pos = sph.center + flat * dist * Mathf.Cos(elev) + dsk.normal * dist * Mathf.Sin(elev);
        var rig = scene.GetRootGameObjects().SelectMany(g => g.GetComponentsInChildren<UnityEngine.Transform>(true)).First(t => t.name == "XR Origin Hands (XR Rig)");
        Restore();

        var vp = scene.GetRootGameObjects().FirstOrDefault(g => g.name == "ViewPoint")?.transform ?? new GameObject("ViewPoint").transform;
        vp.position = pos;
        vp.rotation = Quaternion.LookRotation(Vector3.ProjectOnPlane(sph.center - pos, Vector3.up), Vector3.up); // level for VR
        rig.SetParent(vp, false);
        rig.localPosition = Vector3.zero; rig.localRotation = Quaternion.identity;
        Log($"ESCENA3 ViewPoint at {pos} (dist {dist:0.0}), rig moved there");
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);

        clip.SampleAnimation(root, 12.7f);
        var xr = rig.GetComponentsInChildren<Camera>(true).First(c => c.enabled);
        var eye = new GameObject("_eye").transform;
        eye.position = xr.transform.position;
        eye.LookAt(sph.center, Vector3.up);
        var eyeCam = eye.gameObject.AddComponent<Camera>(); eyeCam.enabled = false;
        RenderFrom(eyeCam, "Logs/cam3_ESCENA3.png", () => { Object.DestroyImmediate(eye.gameObject); Restore(); Log("CAM3 DONE"); });
    }

    // render ESCENA3 from its ViewPoint (no changes saved)
    static void View3()
    {
        var scene = EditorSceneManager.OpenScene("Assets/Scenes/ESCENAS/ESCENA3.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == "ESCENA3");
        var clip = AssetDatabase.LoadAllAssetsAtPath(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        clip.SampleAnimation(root, 12.7f);
        var bh = root.transform.Find("ESCENA3_ROOT/Armature/Bone/BlackHole_VFX");
        var xr = scene.GetRootGameObjects().First(g => g.name == "ViewPoint").GetComponentsInChildren<Camera>(true).First(c => c.enabled);
        var eye = new GameObject("_eye").transform;
        eye.position = xr.transform.position; eye.LookAt(bh.position, Vector3.up);
        var eyeCam = eye.gameObject.AddComponent<Camera>(); eyeCam.enabled = false;
        var close = new GameObject("_close").transform;
        close.position = bh.position + (eye.position - bh.position).normalized * 60f; close.LookAt(bh.position, Vector3.up);
        var closeCam = close.gameObject.AddComponent<Camera>(); closeCam.enabled = false;
        RenderFrom(eyeCam, "Logs/e3view.png", () => RenderFrom(closeCam, "Logs/e3close.png", () => { Object.DestroyImmediate(eye.gameObject); Object.DestroyImmediate(close.gameObject); Log("E3VIEW DONE"); }));
    }

    // ---------------- ESCENA3: ship readability + impact ----------------
    const string TimelinePath = "Assets/Scenes/ESCENAS/e3_timeline.playable";
    const float ImpactTime = 12.0f; // frame 1728, when the ship hits the horizon (the old flash starts here)

    static (VFXBasicSpawner sp, VFXBasicInitialize init, VFXBasicUpdate up) NewSystem(VFXGraph g, Vector2 at, uint capacity, VFXSpace space, float burst, float rate, AABox bounds, string label)
    {
        var sp = ScriptableObject.CreateInstance<VFXBasicSpawner>();
        if (burst > 0)
        {
            var b = ScriptableObject.CreateInstance<VFXSpawnerBurst>(); sp.AddChild(b);
            b.inputSlots.First(s => s.name == "Count").value = burst;
        }
        else
        {
            var r = ScriptableObject.CreateInstance<VFXSpawnerConstantRate>(); sp.AddChild(r);
            r.inputSlots.First(s => s.name == "Rate").value = rate;
        }
        var init = ScriptableObject.CreateInstance<VFXBasicInitialize>();
        var up = ScriptableObject.CreateInstance<VFXBasicUpdate>();
        g.AddChild(sp); g.AddChild(init); g.AddChild(up);
        sp.position = at + new Vector2(jit.Next(-30, 31), -540); init.position = at + new Vector2(jit.Next(-25, 26), -280); up.position = at + new Vector2(jit.Next(-20, 21), 190);
        sp.LinkTo(init); init.LinkTo(up);
        var data = (VFXDataParticle)init.GetData();
        data.SetSettingValue("capacity", capacity);
        data.SetSettingValue("boundsMode", BoundsSettingMode.Manual);
        data.space = space;
        init.inputSlots.First(s => s.name == "bounds").value = bounds;
        sp.label = label;
        return (sp, init, up);
    }

    static VFXPlanarPrimitiveOutput Additive(VFXGraph g, VFXBasicUpdate up, Vector2 at, string label, Texture2D tex = null)
    {
        var o = ScriptableObject.CreateInstance<VFXPlanarPrimitiveOutput>();
        o.SetSettingValue("blendMode", VFXAbstractRenderedOutput.BlendMode.Additive);
        g.AddChild(o);
        o.position = at + new Vector2(jit.Next(-30, 31), 470);
        up.LinkTo(o);
        if (tex) o.inputSlots.First(s => s.property.type == typeof(Texture2D)).value = tex;
        o.label = label;
        return o;
    }

    static AttributeFromCurve OverLife(VFXContext ctx, string attribute, params Keyframe[] keys)
    {
        var c = ScriptableObject.CreateInstance<AttributeFromCurve>();
        c.SetSettingValue("attribute", attribute);
        ctx.AddChild(c);
        c.inputSlots[0].value = new AnimationCurve(keys);
        return c;
    }

    // glowing trail behind the ship, simulated in world space so it stays where the ship has been
    static VisualEffectAsset MakeShipTrail(string path, Vector3 worldCenter)
    {
        if (File.Exists(path)) AssetDatabase.DeleteAsset(path);
        var asset = VisualEffectAssetEditorUtility.CreateNewAsset(path);
        var res = asset.GetOrCreateResource(); var g = res.GetOrCreateGraph();
        var (sp, init, up) = NewSystem(g, Vector2.zero, 600, VFXSpace.World, 0, 220f, new AABox { center = worldCenter, size = Vector3.one * 700 }, "Engine Exhaust");
        var pos = ScriptableObject.CreateInstance<PositionShape>();
        pos.SetSettingValue("shape", PositionShapeBase.Type.Sphere);
        init.AddChild(pos);
        var sph = TArcSphere.defaultValue; sph.sphere.radius = 0.35f;
        SetSlot(pos, "arcSphere", sph);
        init.AddChild(SetAttrRandom("lifetime", 0.5f, 1.1f));
        init.AddChild(SetAttrRandom("size", 0.5f, 1.2f));
        init.AddChild(SetAttrRandom("color", new Vector3(8f, 4f, 1.5f), new Vector3(9f, 6.5f, 3.5f)));
        init.label = "Born at the Ship"; up.label = "Stays Behind";
        var o = Additive(g, up, Vector2.zero, "Glow Trail");
        OverLife(o, "alpha", new Keyframe(0, 1), new Keyframe(1, 0));
        var shrink = OverLife(o, "size", new Keyframe(0, 1), new Keyframe(1, 0.2f));
        shrink.SetSettingValue("Composition", AttributeCompositionMode.Multiply);
        res.WriteAssetWithSubAssets();
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        return AssetDatabase.LoadAssetAtPath<VisualEffectAsset>(path);
    }

    // the hit: one big flash, a burst of sparks and a shockwave ring along the disk. Plays when the object is enabled.
    static VisualEffectAsset MakeImpact(string path, Texture2D ring)
    {
        if (File.Exists(path)) AssetDatabase.DeleteAsset(path);
        var asset = VisualEffectAssetEditorUtility.CreateNewAsset(path);
        var res = asset.GetOrCreateResource(); var g = res.GetOrCreateGraph();
        var box = new AABox { center = Vector3.zero, size = Vector3.one * 400 };

        var flash = NewSystem(g, new Vector2(-700, 0), 4, VFXSpace.Local, 1, 0, box, "Flash");
        flash.init.AddChild(SetAttr("lifetime", 0.55f));
        flash.init.AddChild(SetAttr("color", new Vector3(14f, 10f, 7f)));
        var fo = Additive(g, flash.up, new Vector2(-700, 0), "Flash");
        OverLife(fo, "size", new Keyframe(0, 15), new Keyframe(0.18f, 95), new Keyframe(1, 120));
        OverLife(fo, "alpha", new Keyframe(0, 1), new Keyframe(0.35f, 0.7f), new Keyframe(1, 0));

        var sparks = NewSystem(g, new Vector2(0, 0), 700, VFXSpace.Local, 600, 0, box, "Sparks");
        var blast = ScriptableObject.CreateInstance<VelocitySpherical>();
        blast.SetSettingValue("composition", AttributeCompositionMode.Overwrite);
        blast.SetSettingValue("speedMode", VelocityBase.SpeedMode.Random);
        sparks.init.AddChild(blast);
        SetSlot(blast, "MinSpeed", 18f); SetSlot(blast, "MaxSpeed", 75f);
        sparks.init.AddChild(SetAttrRandom("lifetime", 0.9f, 2.4f));
        sparks.init.AddChild(SetAttrRandom("size", 0.25f, 0.8f));
        sparks.init.AddChild(SetAttrRandom("color", new Vector3(9f, 6f, 3f), new Vector3(10f, 3f, 0.8f)));
        var drag = ScriptableObject.CreateInstance<Drag>();
        sparks.up.AddChild(drag);
        SetSlot(drag, "dragCoefficient", 1.6f);
        var so = Additive(g, sparks.up, new Vector2(0, 0), "Sparks");
        OverLife(so, "alpha", new Keyframe(0, 1), new Keyframe(0.6f, 0.8f), new Keyframe(1, 0));

        var wave = NewSystem(g, new Vector2(700, 0), 4, VFXSpace.Local, 1, 0, box, "Shockwave");
        wave.init.AddChild(SetAttr("lifetime", 1.4f));
        wave.init.AddChild(SetAttr("color", new Vector3(3f, 1.8f, 0.8f)));
        var wo = Additive(g, wave.up, new Vector2(700, 0), "Shockwave Ring (lies on the disk)", ring);
        wo.AddChild(SetAttr("angle", new Vector3(90, 0, 0)));
        OverLife(wo, "size", new Keyframe(0, 6), new Keyframe(1, 115));
        OverLife(wo, "alpha", new Keyframe(0, 0.55f), new Keyframe(0.4f, 0.3f), new Keyframe(1, 0));

        res.WriteAssetWithSubAssets();
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        return AssetDatabase.LoadAssetAtPath<VisualEffectAsset>(path);
    }

    // ESCENA3 only: a gritty base look, plus a harder hit while the impact is on
    static VolumeProfile GritProfile(string path, float grain, FilmGrainLookup grainType, float fringe, float vignette, float contrast, float exposure)
    {
        AssetDatabase.DeleteAsset(path);
        var p = ScriptableObject.CreateInstance<VolumeProfile>();
        AssetDatabase.CreateAsset(p, path);
        var fg = p.Add<FilmGrain>(true); fg.type.Override(grainType); fg.intensity.Override(grain); fg.response.Override(0.6f);
        p.Add<ChromaticAberration>(true).intensity.Override(fringe);
        var vg = p.Add<Vignette>(true); vg.intensity.Override(vignette); vg.smoothness.Override(0.45f);
        var ca = p.Add<ColorAdjustments>(true); ca.contrast.Override(contrast); ca.postExposure.Override(exposure);
        foreach (var c in p.components) { c.hideFlags = HideFlags.HideInInspector | HideFlags.HideInHierarchy; AssetDatabase.AddObjectToAsset(c, p); }
        EditorUtility.SetDirty(p);
        return p;
    }

    static void Impact3()
    {
        var ringPath = $"{Art}/ShockRing.png";
        var ti = (TextureImporter)AssetImporter.GetAtPath(ringPath);
        ti.alphaIsTransparency = true; ti.wrapMode = TextureWrapMode.Clamp; ti.SaveAndReimport();

        var scene = EditorSceneManager.OpenScene("Assets/Scenes/ESCENAS/ESCENA3.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == "ESCENA3");
        var fbxRoot = root.transform.Find("ESCENA3_ROOT");
        var fbxPath = AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar);
        var clip = AssetDatabase.LoadAllAssetsAtPath(fbxPath).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        var saved = root.GetComponentsInChildren<UnityEngine.Transform>(true).Select(t => (t, t.localPosition, t.localRotation, t.localScale)).ToArray();
        void Restore() { foreach (var (t, p, r, s) in saved) { if (!t) continue; t.localPosition = p; t.localRotation = r; t.localScale = s; } }

        // 1) back to the original camera: rig rides UnityCamera again, ViewPoint goes away
        var unityCam = fbxRoot.Find("UnityCamera");
        var src = AssetDatabase.LoadAssetAtPath<GameObject>(fbxPath).transform.Find("ESCENA3_ROOT/UnityCamera");
        unityCam.localPosition = src.localPosition; unityCam.localRotation = src.localRotation;
        var rig = scene.GetRootGameObjects().SelectMany(g => g.GetComponentsInChildren<UnityEngine.Transform>(true)).First(t => t.name == "XR Origin Hands (XR Rig)");
        rig.SetParent(unityCam, false); rig.localPosition = Vector3.zero; rig.localRotation = Quaternion.identity;
        var vp = scene.GetRootGameObjects().FirstOrDefault(g => g.name == "ViewPoint");
        if (vp) Object.DestroyImmediate(vp);
        saved = root.GetComponentsInChildren<UnityEngine.Transform>(true).Select(t => (t, t.localPosition, t.localRotation, t.localScale)).ToArray();

        // 2) hotter engine so the ship reads as a bright point from far away
        var engine = AssetDatabase.LoadAssetAtPath<Material>("Assets/TEST_ASSETS/ESCENA3/materiales/Engine.mat");
        engine.SetColor("_EmissionColor", new Color(1f, 0.25f, 0.06f) * 30f);
        EditorUtility.SetDirty(engine);

        // where things are at the moment of impact
        clip.SampleAnimation(root, ImpactTime + 0.2f);
        var sph = Measure(fbxRoot.Find("BH_02").GetComponent<SkinnedMeshRenderer>());
        var bhVfx = fbxRoot.Find("Armature/Bone/BlackHole_VFX");
        var flashSpot = fbxRoot.Find("destello_horizonte").position;
        Restore();

        // 3) trail on the ship
        var shipBone = fbxRoot.Find("Ship_rig/DEF-ship");
        var old = shipBone.Find("ShipTrail"); if (old) Object.DestroyImmediate(old.gameObject);
        var trail = new GameObject("ShipTrail");
        trail.transform.SetParent(shipBone, false);
        trail.AddComponent<VisualEffect>().visualEffectAsset = MakeShipTrail($"{Root}/VFX/VFXGraph_ShipTrail.vfx", sph.center);

        // 4) impact effect at the old flash spot, lying on the disk plane, off until the timeline turns it on
        foreach (var g in scene.GetRootGameObjects().Where(g => g.name == "Impact")) Object.DestroyImmediate(g);
        var impact = new GameObject("Impact");
        // pulled out of the horizon toward the viewer so the sphere doesn't swallow half of it
        var toCam = (unityCam.position - sph.center).normalized;
        var anchor = sph.center + ((flashSpot - sph.center).normalized * 0.6f + toCam * 0.8f).normalized * sph.radius * 1.15f;
        impact.transform.SetPositionAndRotation(flashSpot, bhVfx.rotation);
        impact.AddComponent<VisualEffect>().visualEffectAsset = MakeImpact($"{Root}/VFX/VFXGraph_Impact.vfx", AssetDatabase.LoadAssetAtPath<Texture2D>(ringPath));
        foreach (var g in scene.GetRootGameObjects().Where(g => g.name == "Grit Volume")) Object.DestroyImmediate(g);
        AssetDatabase.DeleteAsset("Assets/TEST_ASSETS/ESCENA3/ESCENA3_Grit.asset");
        AssetDatabase.DeleteAsset("Assets/TEST_ASSETS/ESCENA3/ESCENA3_Hit.asset");
        impact.SetActive(false);

        // 5) impact light on destello_luz (it had zero power in Blender)
        var lightGo = fbxRoot.Find("destello_luz").gameObject;
        if (!lightGo.TryGetComponent<Light>(out var lamp)) lamp = lightGo.AddComponent<Light>();
        lamp.type = LightType.Point; lamp.color = new Color(1f, 0.72f, 0.45f); lamp.range = 260f; lamp.intensity = 0f; lamp.shadows = LightShadows.None;

        // 6) timeline: impact on at the hit, light pulse
        var tl = AssetDatabase.LoadAssetAtPath<TimelineAsset>(TimelinePath);
        var director = scene.GetRootGameObjects().First(g => g.name == "director").GetComponent<PlayableDirector>();
        foreach (var t in tl.GetOutputTracks().Where(t => t.name == "impact" || t.name == "impact light").ToArray()) tl.DeleteTrack(t);
        var act = tl.CreateTrack<ActivationTrack>("impact");
        var on = act.CreateDefaultClip(); on.start = ImpactTime; on.duration = 4;
        director.SetGenericBinding(act, impact);
        var lightTrack = tl.CreateTrack<AnimationTrack>("impact light");
        var pulse = new AnimationClip { name = "impact light" };
        AnimationUtility.SetEditorCurve(pulse, EditorCurveBinding.FloatCurve("ESCENA3_ROOT/destello_luz", typeof(Light), "m_Intensity"),
            new AnimationCurve(new Keyframe(0, 0), new Keyframe(ImpactTime - 0.05f, 0), new Keyframe(ImpactTime + 0.15f, 90), new Keyframe(ImpactTime + 0.9f, 12), new Keyframe(ImpactTime + 1.8f, 0)));
        foreach (var o in AssetDatabase.LoadAllAssetsAtPath(TimelinePath).OfType<AnimationClip>().Where(c => c.name == "impact light").ToArray()) AssetDatabase.RemoveObjectFromAsset(o);
        AssetDatabase.AddObjectToAsset(pulse, tl);
        lightTrack.CreateClip(pulse).start = 0;
        director.SetGenericBinding(lightTrack, root.GetComponent<Animator>());
        EditorUtility.SetDirty(tl); EditorUtility.SetDirty(director);

        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);
        AssetDatabase.SaveAssets();
        Log("ESCENA3 impact saved");

        // renders from the player's camera: the dive, and just after the hit
        var xr = rig.GetComponentsInChildren<Camera>(true).First(c => c.enabled);
        StepRender(root, clip, xr, impact, trail.GetComponent<VisualEffect>(), lamp, ImpactTime - 1.3f, ImpactTime - 0.35f, "Logs/e3_dive.png", () =>
            StepRender(root, clip, xr, impact, trail.GetComponent<VisualEffect>(), lamp, ImpactTime - 1.0f, ImpactTime + 0.3f, "Logs/e3_hit.png", () => { Restore(); impact.SetActive(false); lamp.intensity = 0; Log("IMPACT DONE"); }));
    }

    static void ImpactView()
    {
        var scene = EditorSceneManager.OpenScene("Assets/Scenes/ESCENAS/ESCENA3.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == "ESCENA3");
        var fbxRoot = root.transform.Find("ESCENA3_ROOT");
        var clip = AssetDatabase.LoadAllAssetsAtPath(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        var impact = scene.GetRootGameObjects().First(g => g.name == "Impact");
        var trail = fbxRoot.Find("Ship_rig/DEF-ship/ShipTrail").GetComponent<VisualEffect>();
        var lamp = fbxRoot.Find("destello_luz").GetComponent<Light>();
        var xr = fbxRoot.Find("UnityCamera").GetComponentsInChildren<Camera>(true).First(c => c.enabled);
        StepRender(root, clip, xr, impact, trail, lamp, ImpactTime - 2.0f, ImpactTime - 0.35f, "Logs/e3_dive.png", () =>
            StepRender(root, clip, xr, impact, trail, lamp, ImpactTime - 1.0f, ImpactTime + 0.25f, "Logs/e3_hit.png", () =>
                StepRender(root, clip, xr, impact, trail, lamp, ImpactTime - 1.0f, ImpactTime + 0.8f, "Logs/e3_after.png", () => { impact.SetActive(false); lamp.intensity = 0; Log("IMPACTVIEW DONE"); })));
    }

    static void Tweak()
    {
        try { TweakInner(); } catch (Exception e) { Debug.LogError("[BLACKHOLE] TWEAK FAILED " + e); }
    }

    static VFXGraph GraphAt(string path) => AssetDatabase.LoadAssetAtPath<VisualEffectAsset>(path).GetOrCreateResource().GetOrCreateGraph();
    static void SaveGraph(VFXGraph g, string path) { g.GetResource().WriteAssetWithSubAssets(); AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate); }

    static void TweakInner()
    {
        // which way the disk scrolls: Blender vertex (6.97, 0.69, 0) has uv (1/64, 0); a flip on import reverses the spin
        var ringMesh = AssetDatabase.LoadAllAssetsAtPath($"{Art}/Ring01.fbx").OfType<Mesh>().First();
        var uvs = ringMesh.uv; var vs = ringMesh.vertices;
        int vi = Enumerable.Range(0, vs.Length).OrderBy(k => (uvs[k] - new Vector2(1f / 64, 0)).sqrMagnitude).First();
        bool flipped = vs[vi].x * vs[vi].y < 0;
        var discSpin = flipped ? Vector3.up : Vector3.down; // in the Ring's own space
        Log($"ring vertex {vs[vi]} uv {uvs[vi]} flipped={flipped} disc spins around {discSpin}");

        // particles: VelocityTangent pushes along cross(radial, axis), i.e. they turn around -axis
        var pPath = Root + "/VFX/VFXGraph_Particles.vfx";
        var pg = GraphAt(pPath);
        var orbit = pg.children.OfType<VFXContext>().SelectMany(c => c.children).OfType<VelocityTangent>().First();
        SetSlot(orbit, "axis", new Line { start = Vector3.zero, end = -discSpin });
        SaveGraph(pg, pPath);

        var scene = EditorSceneManager.OpenScene("Assets/Scenes/ESCENAS/ESCENA3.unity", OpenSceneMode.Single);
        var root = scene.GetRootGameObjects().First(g => g.name == "ESCENA3");
        var fbxRoot = root.transform.Find("ESCENA3_ROOT");
        var clip = AssetDatabase.LoadAllAssetsAtPath(AssetDatabase.GetAssetPath(root.GetComponent<Animator>().avatar)).OfType<AnimationClip>().First(c => !c.name.StartsWith("__preview__"));
        var saved = root.GetComponentsInChildren<UnityEngine.Transform>(true).Select(t => (t, t.localPosition, t.localRotation, t.localScale)).ToArray();
        void Restore() { foreach (var (t, p, r, s) in saved) { if (!t) continue; t.localPosition = p; t.localRotation = r; t.localScale = s; } }
        clip.SampleAnimation(root, ImpactTime + 0.2f);
        var sph = Measure(fbxRoot.Find("BH_02").GetComponent<SkinnedMeshRenderer>());
        Restore();

        // shockwave: flat on the horizon where the ship hits (tangent to the sphere), and smaller
        var impact = scene.GetRootGameObjects().First(g => g.name == "Impact").transform;
        var radial = impact.position - sph.center;
        var angle = Quaternion.FromToRotation(Vector3.forward, Quaternion.Inverse(impact.rotation) * radial.normalized).eulerAngles;
        Log($"impact {radial.magnitude:0.0} from the centre, sphere r {sph.radius:0.0}, impact scale {impact.lossyScale}, wave angle {angle}");
        var iPath = Root + "/VFX/VFXGraph_Impact.vfx";
        var ig = GraphAt(iPath);
        var wo = ig.children.OfType<VFXPlanarPrimitiveOutput>().First(o => o.label.StartsWith("Shockwave"));
        wo.label = "Shockwave Ring (tangent to the horizon)";
        wo.children.OfType<SetAttribute>().First().inputSlots[0].value = angle;
        float R = sph.radius;
        var curves = wo.children.OfType<AttributeFromCurve>().ToArray();
        curves[0].inputSlots[0].value = new AnimationCurve(new Keyframe(0, R * 0.05f), new Keyframe(0.35f, R * 0.5f), new Keyframe(1, R * 0.75f));
        curves[1].inputSlots[0].value = new AnimationCurve(new Keyframe(0, 0.5f), new Keyframe(0.4f, 0.3f), new Keyframe(1, 0));
        // born on the horizon itself, not at the flash spot a bit in front of it
        var waveInit = wo.inputContexts.First().inputContexts.First();
        foreach (var b in waveInit.children.OfType<SetAttribute>().Where(b => b.attribute == "position").ToArray()) waveInit.RemoveChild(b);
        waveInit.AddChild(SetAttr("position", new Position { position = Quaternion.Inverse(impact.rotation) * (sph.center + radial.normalized * R - impact.position) }));
        waveInit.children.OfType<SetAttribute>().First(b => b.attribute == "color").inputSlots[0].value = new Vector3(2.6f, 1.4f, 0.6f);
        SaveGraph(ig, iPath);

        // rocks swing around the hole on top of their fall
        foreach (var g in scene.GetRootGameObjects().Where(g => g.name == "Rock Swirl")) Object.DestroyImmediate(g);
        var swirl = new GameObject("Rock Swirl").AddComponent(Type.GetType("RockSwirl, Assembly-CSharp"));
        var so = new SerializedObject(swirl);
        so.FindProperty("disc").objectReferenceValue = fbxRoot.Find("Armature/Bone/BlackHole_VFX/Ring");
        var rocks = fbxRoot.Cast<UnityEngine.Transform>().Where(t => t.name.StartsWith("roca") || t.name.StartsWith("rcoa")).ToArray();
        var arr = so.FindProperty("rocks"); arr.arraySize = rocks.Length;
        for (int k = 0; k < rocks.Length; k++) arr.GetArrayElementAtIndex(k).objectReferenceValue = rocks[k];
        so.FindProperty("director").objectReferenceValue = scene.GetRootGameObjects().First(g => g.name == "director").GetComponent<PlayableDirector>();
        so.FindProperty("speed").floatValue = 1.5f;
        so.ApplyModifiedPropertiesWithoutUndo();
        Log($"rock swirl on {rocks.Length} rocks: {string.Join(",", rocks.Select(r => r.name))}");
        EditorSceneManager.MarkSceneDirty(scene); EditorSceneManager.SaveScene(scene); AssetDatabase.SaveAssets();
        Log("TWEAK saved");

        var trail = fbxRoot.Find("Ship_rig/DEF-ship/ShipTrail").GetComponent<VisualEffect>();
        var lamp = fbxRoot.Find("destello_luz").GetComponent<Light>();
        var xr = fbxRoot.Find("UnityCamera").GetComponentsInChildren<Camera>(true).First(c => c.enabled);
        void Done() { Restore(); impact.gameObject.SetActive(false); lamp.intensity = 0; EditorSceneManager.SaveScene(scene); Log("TWEAK DONE"); }
        StepRender(root, clip, xr, impact.gameObject, trail, lamp, ImpactTime - 1.0f, ImpactTime + 0.3f, "Logs/e3_hit.png", () =>
            StepRender(root, clip, xr, impact.gameObject, trail, lamp, ImpactTime - 1.0f, ImpactTime + 0.6f, "Logs/e3_wave.png", () =>
                StepRender(root, clip, xr, impact.gameObject, trail, lamp, ImpactTime - 1.0f, ImpactTime + 0.8f, "Logs/e3_after.png", Done)));
    }

    // steps the animation like playback (so the trail streaks and the burst ages), then renders
    static void StepRender(GameObject root, AnimationClip clip, Camera view, GameObject impact, VisualEffect trail, Light lamp, float from, float to, string file, Action done)
    {
        float t = from;
        impact.SetActive(false);
        trail.Reinit();
        void Tick()
        {
            const float dt = 1f / 30f;
            t += dt;
            clip.SampleAnimation(root, t);
            var sw = Object.FindAnyObjectByType(Type.GetType("RockSwirl, Assembly-CSharp")) as MonoBehaviour;
            if (sw)
            {
                Object.FindAnyObjectByType<PlayableDirector>().time = t;
                sw.GetType().GetMethod("LateUpdate", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(sw, null);
            }
            if (t >= ImpactTime && !impact.activeSelf) { impact.SetActive(true); impact.GetComponent<VisualEffect>().Reinit(); }
            lamp.intensity = t < ImpactTime ? 0 : Mathf.Lerp(90, 0, (t - ImpactTime) / 1.8f);
            trail.Simulate(dt, 1);
            if (impact.activeSelf) impact.GetComponent<VisualEffect>().Simulate(dt, 1);
            foreach (var v in Object.FindObjectsByType<VisualEffect>().Where(v => v != trail && v.gameObject != impact)) v.Simulate(dt, 1);
            if (t < to) return;
            EditorApplication.update -= Tick;
            var go = new GameObject("_preview");
            go.transform.SetPositionAndRotation(view.transform.position, view.transform.rotation);
            var cam = go.AddComponent<Camera>();
            cam.fieldOfView = 70; cam.nearClipPlane = 0.1f; cam.farClipPlane = 100000; cam.allowHDR = true;
            var data = go.AddComponent<UniversalAdditionalCameraData>();
            data.renderPostProcessing = true; data.requiresColorOption = CameraOverrideOption.On;
            var rt = new RenderTexture(1280, 720, 24, RenderTextureFormat.DefaultHDR);
            cam.targetTexture = rt; cam.Render(); cam.Render(); cam.targetTexture = null;
            var ldr = RenderTexture.GetTemporary(1280, 720, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            Graphics.Blit(rt, ldr); RenderTexture.active = ldr;
            var tex = new Texture2D(1280, 720, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0); tex.Apply(); RenderTexture.active = null;
            File.WriteAllBytes(file, tex.EncodeToPNG());
            RenderTexture.ReleaseTemporary(ldr); rt.Release(); Object.DestroyImmediate(go);
            Log("PREVIEW saved " + file);
            done();
        }
        EditorApplication.update += Tick;
    }

    static void RenderFrom(Camera source, string file, Action done)
    {
        var go = new GameObject("_preview");
        go.transform.SetPositionAndRotation(source.transform.position, source.transform.rotation);
        var cam = go.AddComponent<Camera>();
        cam.fieldOfView = 60; cam.nearClipPlane = 0.1f; cam.farClipPlane = 100000; cam.allowHDR = true;
        cam.clearFlags = CameraClearFlags.Skybox;
        var data = go.AddComponent<UniversalAdditionalCameraData>();
        data.renderPostProcessing = true; data.requiresColorOption = CameraOverrideOption.On;
        int frames = 0;
        void Tick()
        {
            foreach (var v in Object.FindObjectsByType<VisualEffect>()) v.Simulate(1f / 60f, 1);
            if (++frames < 120) { SceneView.RepaintAll(); return; }
            EditorApplication.update -= Tick;
            var rt = new RenderTexture(1280, 720, 24, RenderTextureFormat.DefaultHDR);
            cam.targetTexture = rt; cam.Render(); cam.Render(); cam.targetTexture = null;
            var ldr = RenderTexture.GetTemporary(1280, 720, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            Graphics.Blit(rt, ldr);
            RenderTexture.active = ldr;
            var tex = new Texture2D(1280, 720, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0); tex.Apply();
            RenderTexture.active = null;
            File.WriteAllBytes(file, tex.EncodeToPNG());
            RenderTexture.ReleaseTemporary(ldr); rt.Release();
            Object.DestroyImmediate(go);
            Log("PREVIEW saved " + file);
            done();
        }
        EditorApplication.update += Tick;
    }

    // ---------------- preview ----------------
    [MenuItem("Tools/BlackHoleTest/Render Preview")]
    static void RenderPreview() => RenderPreviewAt("Logs/blackholetest_preview.png", null, false);

    static void RenderPreviewAt(string file, Vector3? topPos, bool hideSphere)
    {
        var sphere = GameObject.Find("VFXGraph_BlackHole");
        if (hideSphere && sphere) sphere.SetActive(false);
        var cam0 = Camera.main.transform;
        var (p0, r0) = (cam0.position, cam0.rotation);
        if (topPos.HasValue) cam0.SetPositionAndRotation(topPos.Value, Quaternion.Euler(90, 0, 0));
        int frames = 0;
        void Tick()
        {
            foreach (var v in Object.FindObjectsByType<VisualEffect>()) v.Simulate(1f / 60f, 1);
            if (++frames < 90) { SceneView.RepaintAll(); return; }
            EditorApplication.update -= Tick;
            var cam = Camera.main;
            var rt = new RenderTexture(1280, 720, 24, RenderTextureFormat.DefaultHDR);
            cam.targetTexture = rt; cam.Render(); cam.Render(); cam.targetTexture = null;
            var ldr = RenderTexture.GetTemporary(1280, 720, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            Graphics.Blit(rt, ldr);
            RenderTexture.active = ldr;
            var tex = new Texture2D(1280, 720, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0); tex.Apply();
            RenderTexture.active = null;
            File.WriteAllBytes(file, tex.EncodeToPNG());
            RenderTexture.ReleaseTemporary(ldr); rt.Release();
            cam0.SetPositionAndRotation(p0, r0);
            if (sphere) sphere.SetActive(true);
            Log("PREVIEW saved");
        }
        EditorApplication.update += Tick;
    }
}

