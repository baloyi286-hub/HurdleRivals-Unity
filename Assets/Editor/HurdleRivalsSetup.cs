#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace HurdleRivals.Editor
{
    public static class HurdleRivalsSetup
    {
        [MenuItem("Hurdle Rivals/Configure Project")]
        public static void Configure()
        {
            const string path = "Assets/Scenes/Race.unity";
            Directory.CreateDirectory("Assets/Scenes");
            if (!File.Exists(path))
            {
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                var root = new GameObject("Hurdle Rivals Bootstrap");
                root.AddComponent<HurdleRivals.Runtime.RaceBootstrap>();
                EditorSceneManager.SaveScene(scene, path);
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(path, true) };
            PlayerSettings.productName = "Hurdle Rivals";
            PlayerSettings.companyName = "Hurdle Rivals";
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.hurdlerivals.tv");
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            AssetDatabase.SaveAssets();
        }
    }
}
#endif
