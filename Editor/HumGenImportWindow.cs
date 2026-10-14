// The import settings of one or more Human Generator exports: use the project defaults or
// override them for these files. Opened from the context menu of an .fbx, from the Human
// Generator 3D menu, and by itself after a new character was imported in the editor.
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace HumGen3D.Companion
{
    public sealed class HumGenImportWindow : EditorWindow
    {
        const string MenuPath = "Human Generator 3D/Import Settings...";
        const string AssetsMenuPath = "Assets/Human Generator 3D/Import Settings...";

        [SerializeField] List<string> modelPaths = new List<string>();
        [SerializeField] bool overrideDefaults;
        [SerializeField] HumGenImportOptions options;
        [SerializeField] bool firstImport;
        Vector2 scroll;

        [MenuItem(MenuPath, true)]
        [MenuItem(AssetsMenuPath, true)]
        static bool CanOpenForSelection()
        {
            return SelectedModels().Any();
        }

        [MenuItem(MenuPath, false, 20)]
        [MenuItem(AssetsMenuPath, false, 1000)]
        static void OpenForSelection()
        {
            Open(SelectedModels(), false);
        }

        /// <summary>Opens the window for the models; after their first import it says so.</summary>
        public static void Open(IEnumerable<string> paths, bool afterFirstImport)
        {
            var window = GetWindow<HumGenImportWindow>(true, "Human Generator 3D Import Settings", true);
            var list = paths.Distinct().ToList();
            if (afterFirstImport && window.firstImport)
                list = window.modelPaths.Union(list).ToList();
            window.modelPaths = list;
            window.firstImport = afterFirstImport;
            window.Load();
            window.minSize = new Vector2(380, 360);
            window.Show();
        }

        static IEnumerable<string> SelectedModels()
        {
            foreach (var guid in Selection.assetGUIDs)
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var candidates = AssetDatabase.IsValidFolder(path)
                    ? Directory.GetFiles(path, "*.fbx", SearchOption.AllDirectories).Select(p => p.Replace('\\', '/'))
                    : new[] { path };
                foreach (var candidate in candidates)
                {
                    var export = HumGenExport.FromModelPath(candidate);
                    if (export != null && !export.IsClip)
                        yield return export.ModelPath;
                }
            }
        }

        // The options of the first model, or the project defaults when it has none
        void Load()
        {
            var file = modelPaths.Select(p => HumGenFileOptions.Read(AssetImporter.GetAtPath(p))).FirstOrDefault(f => f != null);
            overrideDefaults = file != null && file.overrideDefaults && file.options != null;
            options = overrideDefaults ? file.options.Clone() : HumGenSettings.instance.defaults.Clone();
        }

        void OnGUI()
        {
            modelPaths.RemoveAll(p => AssetImporter.GetAtPath(p) == null);
            if (modelPaths.Count == 0)
            {
                EditorGUILayout.HelpBox("Select the .fbx of a Human Generator export and open this window from its context menu.", MessageType.Info);
                return;
            }
            if (firstImport)
                EditorGUILayout.HelpBox("Imported with the project defaults. Change what the companion sets up for "
                    + (modelPaths.Count == 1 ? "this character" : "these characters") + ", or close this window to keep it.", MessageType.Info);

            EditorGUILayout.LabelField(modelPaths.Count == 1 ? "Character" : "Characters", EditorStyles.boldLabel);
            using (new EditorGUI.IndentLevelScope())
                foreach (var path in modelPaths)
                    EditorGUILayout.LabelField(Path.GetFileName(path), path, EditorStyles.miniLabel);

            var foreign = modelPaths.Where(p => !HumGenFileOptions.IsOurs(AssetImporter.GetAtPath(p))).ToList();
            if (foreign.Count > 0)
                EditorGUILayout.HelpBox("The import settings of " + string.Join(", ", foreign.Select(Path.GetFileName))
                    + " hold user data of another tool; overriding the defaults would replace it.", MessageType.Warning);

            EditorGUILayout.Space(6);
            var useDefaults = EditorGUILayout.ToggleLeft("Use the project defaults", !overrideDefaults);
            if (useDefaults == overrideDefaults)
            {
                overrideDefaults = !useDefaults;
                if (!overrideDefaults)
                    options = HumGenSettings.instance.defaults.Clone();
            }
            using (new EditorGUILayout.HorizontalScope())
            {
                GUILayout.FlexibleSpace();
                if (GUILayout.Button("Edit Project Defaults", EditorStyles.miniButton))
                    SettingsService.OpenProjectSettings("Project/Human Generator 3D");
            }

            EditorGUILayout.Space(4);
            scroll = EditorGUILayout.BeginScrollView(scroll);
            using (new EditorGUI.DisabledScope(!overrideDefaults))
                options.OnGUI();
            EditorGUILayout.EndScrollView();

            EditorGUILayout.Space(6);
            using (new EditorGUILayout.HorizontalScope())
            {
                GUILayout.FlexibleSpace();
                using (new EditorGUI.DisabledScope(!HasChanges()))
                {
                    if (GUILayout.Button("Revert", GUILayout.Width(80)))
                        Load();
                    if (GUILayout.Button("Apply", GUILayout.Width(80)))
                        Apply();
                }
            }
        }

        bool HasChanges()
        {
            foreach (var path in modelPaths)
            {
                var file = HumGenFileOptions.Read(AssetImporter.GetAtPath(path));
                var fileOverrides = file != null && file.overrideDefaults && file.options != null;
                if (fileOverrides != overrideDefaults)
                    return true;
                if (overrideDefaults && JsonUtility.ToJson(file.options) != JsonUtility.ToJson(options))
                    return true;
            }
            return false;
        }

        // Writes the options into the importers of every file of the exports (model, textures, clips)
        // and reimports them: a changed .meta file is reimported by itself
        void Apply()
        {
            var exports = modelPaths.Select(HumGenExport.FromModelPath).Where(e => e != null).ToList();
            AssetDatabase.StartAssetEditing();
            try
            {
                foreach (var export in exports)
                {
                    foreach (var path in new[] { export.ModelPath }.Concat(export.AllTextures()).Concat(export.ClipPaths()))
                    {
                        var importer = AssetImporter.GetAtPath(path);
                        if (importer == null)
                            continue;
                        if (overrideDefaults && (path == export.ModelPath || HumGenFileOptions.IsOurs(importer)))
                            new HumGenFileOptions { overrideDefaults = true, options = options.Clone() }.Write(importer);
                        else if (!overrideDefaults && HumGenFileOptions.Read(importer) != null)
                            importer.userData = "";
                        else
                            continue;
                        EditorUtility.SetDirty(importer);
                        importer.SaveAndReimport();
                    }
                }
            }
            finally
            {
                AssetDatabase.StopAssetEditing();
            }
            firstImport = false;
        }
    }
}
