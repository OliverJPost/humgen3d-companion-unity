// Project-wide settings of the companion, in ProjectSettings/HumGen3DCompanion.asset and under
// Project Settings > Human Generator 3D.
//
// The import of every Human Generator export depends on a custom dependency whose hash is that of
// these settings, so changing them (here, or by pulling a changed file) reimports the characters
// that use the project defaults.
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

namespace HumGen3D.Companion
{
    [FilePath("ProjectSettings/HumGen3DCompanion.asset", FilePathAttribute.Location.ProjectFolder)]
    public sealed class HumGenSettings : ScriptableSingleton<HumGenSettings>
    {
        public const string DependencyName = "HumGen3D.Companion/Settings";
        /// <summary>The version of these settings a save writes; bump it and migrate on load when they change meaning.</summary>
        public const int CurrentVersion = 1;

        /// <summary>Version of the stored settings; 1 when the file has none (0.6.0).</summary>
        public int version = CurrentVersion;

        /// <summary>The options of every export that does not override them.</summary>
        public HumGenImportOptions defaults = new HumGenImportOptions();
        /// <summary>Opens the import settings window after a new character was imported in the editor.</summary>
        public bool showWindowOnFirstImport = true;
        /// <summary>Logs a warning on import when MSAA is off, which the hair cards' alpha to mask needs.</summary>
        public bool warnWithoutMsaa = true;

        public void SaveAndRegister()
        {
            version = CurrentVersion;
            Save(true);
            RegisterDependency();
        }

        /// <summary>Changes the hash of the custom dependency when the project defaults changed.</summary>
        public static void RegisterDependency()
        {
            var hash = Hash128.Compute(JsonUtility.ToJson(instance.defaults));
            AssetDatabase.RegisterCustomDependency(DependencyName, hash);
        }

        [InitializeOnLoadMethod]
        static void RegisterOnLoad()
        {
            // Custom dependencies are not kept between editor sessions
            RegisterDependency();
        }

        [SettingsProvider]
        static SettingsProvider CreateProvider()
        {
            return new SettingsProvider("Project/Human Generator 3D", SettingsScope.Project)
            {
                label = "Human Generator 3D",
                guiHandler = _ => DrawSettings(),
                keywords = new HashSet<string>(new[] { "Human Generator", "HumGen3D", "hair", "skin", "humanoid", "import" }),
            };
        }

        // The defaults being edited on the settings page, applied with its Apply button: every
        // applied change reimports the characters, so not on every change of a slider
        static HumGenImportOptions pending;

        static void DrawSettings()
        {
            var settings = instance;
            if (pending == null)
                pending = settings.defaults.Clone();
            EditorGUILayout.LabelField("Import defaults", EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("How the Human Generator 3D Companion sets up exported characters on import. "
                + "A character can override these in Human Generator 3D > Import Settings (right-click its .fbx). "
                + "Applying reimports the characters that use the defaults.", MessageType.None);
            using (new EditorGUI.IndentLevelScope())
                pending.OnGUI();
            var changed = JsonUtility.ToJson(pending) != JsonUtility.ToJson(settings.defaults);
            using (new EditorGUILayout.HorizontalScope())
            {
                GUILayout.FlexibleSpace();
                if (GUILayout.Button("Reset to Defaults", GUILayout.Width(130)))
                    pending = new HumGenImportOptions();
                using (new EditorGUI.DisabledScope(!changed))
                {
                    if (GUILayout.Button("Revert", GUILayout.Width(70)))
                        pending = settings.defaults.Clone();
                    if (GUILayout.Button("Apply", GUILayout.Width(70)))
                    {
                        settings.defaults = pending.Clone();
                        settings.SaveAndRegister();
                        AssetDatabase.Refresh();
                    }
                }
            }

            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField("Editor", EditorStyles.boldLabel);
            using (new EditorGUI.IndentLevelScope())
            {
                EditorGUI.BeginChangeCheck();
                settings.showWindowOnFirstImport = EditorGUILayout.Toggle(new GUIContent("Show Window On Import", "Open the import settings window after a new character was imported. Never in batch mode."), settings.showWindowOnFirstImport);
                settings.warnWithoutMsaa = EditorGUILayout.Toggle(new GUIContent("Warn Without MSAA", "Log a warning on import when MSAA is off; the soft edges of the hair cards need it."), settings.warnWithoutMsaa);
                if (EditorGUI.EndChangeCheck())
                {
                    settings.version = CurrentVersion;
                    settings.Save(true);
                }
            }
        }
    }
}
