using UnityEngine;
using UnityEngine.SceneManagement;

public class CharacterColorManager : MonoBehaviour
{
    // =========================================================
    // SINGLETON
    // =========================================================

    public static CharacterColorManager Instance;


    // =========================================================
    // SELECTED COLORS
    // =========================================================

    public Color HairColor { get; private set; }
    public Color SkinColor { get; private set; }
    public Color EyeColor { get; private set; }


    // =========================================================
    // SHADER PROPERTY IDs
    // =========================================================

    private static readonly int HairColorID =
        Shader.PropertyToID("_HairColor");

    private static readonly int SkinColorID =
        Shader.PropertyToID("_SkinColor");

    private static readonly int EyeColorID =
        Shader.PropertyToID("_EyeColor");


    // Reusable property block
    private MaterialPropertyBlock propertyBlock;


    // =========================================================
    // START
    // =========================================================

    private void Awake()
    {
        // Prevent duplicate managers
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }

        Instance = this;

        DontDestroyOnLoad(gameObject);

        propertyBlock = new MaterialPropertyBlock();


        // Default colours
        HairColor = HexToColor("FFFFE9");
        SkinColor = HexToColor("FFFCED");
        EyeColor = HexToColor("FFFFFF");


        // Listen for scene changes
        SceneManager.sceneLoaded += OnSceneLoaded;
    }


    // =========================================================
    // CLEANUP
    // =========================================================

    private void OnDestroy()
    {
        if (Instance == this)
        {
            SceneManager.sceneLoaded -= OnSceneLoaded;
        }
    }


    // =========================================================
    // SET COLORS
    // =========================================================

    public void SetHairColor(Color color)
    {
        HairColor = color;
    }


    public void SetSkinColor(Color color)
    {
        SkinColor = color;
    }


    public void SetEyeColor(Color color)
    {
        EyeColor = color;
    }


    // =========================================================
    // SCENE LOADED
    // =========================================================

    private void OnSceneLoaded(
        Scene scene,
        LoadSceneMode mode
    )
    {
        ApplyColorsToAllCharacters();
    }


    // =========================================================
    // APPLY TO ALL CHARACTER RENDERERS
    // =========================================================

    public void ApplyColorsToAllCharacters()
    {
        // Find every Renderer in the currently loaded scene,
        // including inactive objects.
        Renderer[] renderers =
            FindObjectsByType<Renderer>(
                FindObjectsInactive.Include,
                FindObjectsSortMode.None
            );


        foreach (Renderer renderer in renderers)
        {
            ApplyColorsToRenderer(renderer);
        }
    }


    // =========================================================
    // APPLY TO ONE RENDERER
    // =========================================================

    public void ApplyColorsToRenderer(Renderer renderer)
    {
        if (renderer == null)
            return;


        // Check every material on this renderer.
        Material[] materials = renderer.sharedMaterials;


        bool hasCharacterShader = false;


        foreach (Material material in materials)
        {
            if (material == null)
                continue;


            if (material.shader != null &&
                (material.shader.name == "Custom/CharacterRecolorToon" || material.shader.name == "ESCENA67/KidMagic" || material.shader.name == "ESCENA67/KidMagicTransparent" || material.shader.name == "Custom/EyesRecolourToon"))
            {
                hasCharacterShader = true;
                break;
            }
        }


        // This isn't one of our character materials.
        if (!hasCharacterShader)
            return;


        // =====================================================
        // APPLY COLORS
        // =====================================================

        // A renderer only has ONE property block, and SetPropertyBlock replaces it.
        // Read the current one first so values set by other scripts
        // (e.g. MagicDissolveDriver's per-kid Mapping Location) are kept,
        // instead of clearing them.
        renderer.GetPropertyBlock(propertyBlock);

        propertyBlock.SetColor(
            HairColorID,
            HairColor
        );

        propertyBlock.SetColor(
            SkinColorID,
            SkinColor
        );

        propertyBlock.SetColor(
            EyeColorID,
            EyeColor
        );


        renderer.SetPropertyBlock(propertyBlock);
    }


    // =========================================================
    // HEX COLOR CONVERTER
    // =========================================================

    private Color HexToColor(string hex)
    {
        Color color;

        if (ColorUtility.TryParseHtmlString(
            "#" + hex,
            out color
        ))
        {
            return color;
        }


        Debug.LogWarning(
            "Could not convert color: " + hex
        );

        return Color.white;
    }
}