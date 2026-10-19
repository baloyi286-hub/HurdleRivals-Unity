#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace HurdleRivals.Editor
{
    public static class CIBuilder
    {
        public static void Build()
        {
            HurdleRivalsSetup.Configure();
            string target = Environment.GetEnvironmentVariable("BUILD_TARGET") ?? "Android";
            bool android = target.Equals("Android", StringComparison.OrdinalIgnoreCase);
            string output = Environment.GetEnvironmentVariable("BUILD_OUTPUT") ??
                (android ? "Builds/Android/HurdleRivals.apk" : "Builds/StandaloneLinux64/HurdleRivals.x86_64");
            Directory.CreateDirectory(Path.GetDirectoryName(output));
            if (android)
            {
                EditorUserBuildSettings.buildAppBundle = false;
                PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            }
            var options = new BuildPlayerOptions
            {
                scenes = new[] { "Assets/Scenes/Race.unity" },
                locationPathName = output,
                target = android ? BuildTarget.Android : BuildTarget.StandaloneLinux64,
                options = BuildOptions.None
            };
            var report = BuildPipeline.BuildPlayer(options);
            if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
                throw new Exception("Unity build failed: " + report.summary.result);
            Debug.Log("Build successful: " + output);
        }
    }
}
#endif
