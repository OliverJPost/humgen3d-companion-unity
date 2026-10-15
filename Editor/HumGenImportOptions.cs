// What the companion sets up on import, with the defaults it had before these were options.
//
// The project defaults live in ProjectSettings/HumGen3DCompanion.asset (HumGenSettings, edited
// under Project Settings > Human Generator 3D). An export can override them: its options are then
// stored as JSON in the userData of the importers of its files (model, textures, clips), in their
// .meta files, so they are kept on every reimport and travel with the files in version control.
using System;
using UnityEditor;
using UnityEngine;

namespace HumGen3D.Companion
{
    // The enums below are stored by their number in the project settings and the .meta files of
    // the exports: never change or reuse a value, only add new ones.

    public enum HairShading
    {
        /// <summary>The package's hair shader in URP when the export has the flow map of the cards.</summary>
        HairShader = 0,
        /// <summary>The two-sided cutout shader, lit as a flat surface.</summary>
        Cutout = 1,
    }

    public enum SkinShading
    {
        /// <summary>The package's Skin URP shader; in HDRP the Subsurface Scattering material type with a diffusion profile registered in the project.</summary>
        SkinShader = 0,
        /// <summary>Universal Render Pipeline/Lit; in HDRP the standard material type.</summary>
        Lit = 1,
    }

    public enum HaircapSetup
    {
        /// <summary>Faded (Built-in), dithered (URP) or transparent (HDRP), under the hair cards.</summary>
        SetUp = 0,
        /// <summary>Left as Unity's importer made the material.</summary>
        AsImported = 1,
    }

    [Serializable]
    public sealed class HumGenImportOptions
    {
        /// <summary>Off leaves the export as Unity imports it.</summary>
        public bool setUpCharacter = true;
        /// <summary>Rig set to Humanoid with an avatar from the model, the clips copy it; Generic when off.</summary>
        public bool humanoid = true;
        public HairShading hairShading = HairShading.HairShader;
        /// <summary>Alpha below which a hair card texel is cut out.</summary>
        [Range(0f, 1f)] public float hairCutoff = 0.5f;
        public HaircapSetup haircap = HaircapSetup.SetUp;
        public SkinShading skinShading = SkinShading.SkinShader;
        /// <summary>Multiplier of the smoothness map of the skin in URP.</summary>
        [Range(0f, 1f)] public float skinSmoothness = 0.7f;

        public HumGenImportOptions Clone()
        {
            return (HumGenImportOptions)MemberwiseClone();
        }

        /// <summary>
        /// The options an asset of an export is imported with: its own when it overrides the project
        /// defaults. The model, its textures and its clips each carry a copy of the override (the
        /// import settings window writes all of them), as an import cannot rely on reading the
        /// settings of another asset.
        /// </summary>
        public static HumGenImportOptions For(AssetImporter importer)
        {
            var file = HumGenFileOptions.Read(importer);
            if (file != null && file.overrideDefaults && file.options != null)
                return file.options;
            return HumGenSettings.instance.defaults;
        }

        /// <summary>Draws the options with undo-free GUI, for the settings page and the window.</summary>
        public void OnGUI()
        {
            setUpCharacter = EditorGUILayout.Toggle(new GUIContent("Set Up Character", "Off leaves the export as Unity imports it."), setUpCharacter);
            using (new EditorGUI.DisabledScope(!setUpCharacter))
            {
                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField("Rig", EditorStyles.boldLabel);
                humanoid = EditorGUILayout.Toggle(new GUIContent("Humanoid", "Rig set to Humanoid with the avatar created from the model; the animation files of the export copy it. Off sets the rig to Generic."), humanoid);
                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField("Hair", EditorStyles.boldLabel);
                hairShading = (HairShading)EditorGUILayout.EnumPopup(new GUIContent("Card Shading", "URP: Hair Shader lights the cards along their strands from the flow map of the export. Cutout lights them as flat surfaces. Built-in and HDRP always use a cutout."), hairShading);
                hairCutoff = EditorGUILayout.Slider(new GUIContent("Card Cutoff", "Alpha below which a hair card texel is cut out, also the reference of the coverage-preserving mipmaps."), hairCutoff, 0f, 1f);
                haircap = (HaircapSetup)EditorGUILayout.EnumPopup(new GUIContent("Haircap", "Set Up: faded (Built-in), dithered (URP) or transparent (HDRP) under the cards. As Imported leaves the material as Unity made it."), haircap);
                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField("Skin (URP, HDRP)", EditorStyles.boldLabel);
                skinShading = (SkinShading)EditorGUILayout.EnumPopup(new GUIContent("Shader", "Skin Shader: in URP the package's Skin URP shader, with light scattered under the skin; in HDRP the Subsurface Scattering material type with a diffusion profile registered in the project. Lit: Universal Render Pipeline/Lit, or the standard material type in HDRP."), skinShading);
                skinSmoothness = EditorGUILayout.Slider(new GUIContent("Smoothness", "URP: multiplier of the smoothness map of the skin. At 1 the skin looks oiled."), skinSmoothness, 0f, 1f);
            }
        }
    }

    /// <summary>The options of one export, as stored in the userData of the importers of its files.</summary>
    [Serializable]
    internal sealed class HumGenFileOptions
    {
        /// <summary>The version of this data a new write gets; bump it and migrate in Read when the data changes meaning.</summary>
        public const int CurrentVersion = 1;

        // Marks the userData as the companion's, so userData of other tools is left alone
        public string humgen3dCompanion = "import options";
        /// <summary>Version of the data; 1 when it was written without one (0.6.0).</summary>
        public int version = CurrentVersion;
        public bool overrideDefaults;
        public HumGenImportOptions options;

        public static bool IsOurs(AssetImporter importer)
        {
            return importer != null && (string.IsNullOrEmpty(importer.userData) || Read(importer) != null);
        }

        public static HumGenFileOptions Read(AssetImporter importer)
        {
            if (importer == null || string.IsNullOrEmpty(importer.userData) || !importer.userData.Contains("\"humgen3dCompanion\""))
                return null;
            try { return JsonUtility.FromJson<HumGenFileOptions>(importer.userData); }
            catch (ArgumentException) { return null; }
        }

        public void Write(AssetImporter importer)
        {
            version = CurrentVersion;
            importer.userData = JsonUtility.ToJson(this);
        }
    }
}
