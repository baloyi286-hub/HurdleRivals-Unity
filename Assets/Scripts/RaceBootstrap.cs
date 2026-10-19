using UnityEngine;

namespace HurdleRivals.Runtime
{
    /// <summary>Self-contained prototype scene. Replace primitives with animated assets later.</summary>
    public sealed class RaceBootstrap : MonoBehaviour
    {
        private readonly Runner[] runners = new Runner[2];
        private readonly Camera[] cameras = new Camera[2];
        private float nextHurdleZ = 18f;
        private float raceStart;
        private bool finished;
        private string winner = "";

        private void Start()
        {
            Application.targetFrameRate = 60;
            RenderSettings.ambientLight = Color.white;
            CreateBlock("Track", new Vector3(0, -0.2f, 120), new Vector3(13, 0.3f, 260),
                new Color(0.22f, 0.65f, 0.38f));
            for (int i = 0; i < 2; i++)
            {
                var runner = GameObject.CreatePrimitive(PrimitiveType.Capsule);
                runner.name = "Player " + (i + 1);
                runner.transform.position = new Vector3(i == 0 ? -1.6f : 1.6f, 1f, 0f);
                runner.GetComponent<Renderer>().material.color = i == 0 ? Color.cyan : new Color(1f, 0.3f, 0.25f);
                runners[i] = runner.AddComponent<Runner>();
                runners[i].PlayerIndex = i;
                var camObject = new GameObject("Player " + (i + 1) + " Camera");
                var cam = camObject.AddComponent<Camera>();
                cam.rect = new Rect(i * 0.5f, 0f, 0.5f, 1f);
                cam.fieldOfView = 70;
                cameras[i] = cam;
            }
            for (int z = 14; z < 240; z += 14)
                CreateBlock("Hurdle", new Vector3(0, 0.7f, z), new Vector3(10, 1.4f, 0.28f), Color.yellow);
            CreateBlock("Finish", new Vector3(0, 0.03f, 245), new Vector3(13, 0.1f, 1f), Color.white);
            raceStart = Time.time;
        }

        private GameObject CreateBlock(string label, Vector3 position, Vector3 size, Color color)
        {
            var block = GameObject.CreatePrimitive(PrimitiveType.Cube);
            block.name = label;
            block.transform.position = position;
            block.transform.localScale = size;
            block.GetComponent<Renderer>().material.color = color;
            return block;
        }

        private void Update()
        {
            if (finished) return;
            for (int i = 0; i < 2; i++)
            {
                var runner = runners[i];
                if (runner.transform.position.z >= 245f)
                {
                    finished = true;
                    winner = "PLAYER " + (i + 1) + " WINS!";
                }
                cameras[i].transform.position = runner.transform.position + new Vector3(0, 4.4f, -8f);
                cameras[i].transform.LookAt(runner.transform.position + Vector3.forward * 9f);
            }
        }

        private void OnGUI()
        {
            GUI.skin.label.fontSize = Mathf.Max(18, Screen.height / 30);
            GUI.Label(new Rect(16, 10, Screen.width - 32, 80),
                finished ? winner : "HURDLE RIVALS  |  P1: W jump, A/D steer, S push   |   P2: Up jump, Left/Right steer, Down push");
            if (finished && GUI.Button(new Rect(Screen.width / 2f - 90, 85, 180, 60), "REMATCH"))
                UnityEngine.SceneManagement.SceneManager.LoadScene(0);
        }
    }

    public sealed class Runner : MonoBehaviour
    {
        public int PlayerIndex;
        private float verticalVelocity;
        private float knockdownUntil;
        private float lastPush;
        private float lastObstacleZ = -100f;
        private const float Speed = 8f;
        private void Update()
        {
            float dt = Time.deltaTime;
            bool jump = Input.GetKeyDown(PlayerIndex == 0 ? KeyCode.W : KeyCode.UpArrow);
            bool push = Input.GetKeyDown(PlayerIndex == 0 ? KeyCode.S : KeyCode.DownArrow);
            float steer = (Input.GetKey(PlayerIndex == 0 ? KeyCode.D : KeyCode.RightArrow) ? 1f : 0f)
                        - (Input.GetKey(PlayerIndex == 0 ? KeyCode.A : KeyCode.LeftArrow) ? 1f : 0f);
            if (Time.time < knockdownUntil) return;
            var pos = transform.position;
            if (jump && pos.y <= 1.02f) verticalVelocity = 8f;
            verticalVelocity -= 20f * dt;
            pos.y = Mathf.Max(1f, pos.y + verticalVelocity * dt);
            if (pos.y <= 1f) verticalVelocity = 0f;
            pos.x = Mathf.Clamp(pos.x + steer * 5f * dt, -5f, 5f);
            pos.z += Speed * dt;
            transform.position = pos;
            if (pos.z > 12f && pos.z < 244f)
            {
                float nearest = Mathf.Round((pos.z - 14f) / 14f) * 14f + 14f;
                if (Mathf.Abs(nearest - pos.z) < 0.3f && Mathf.Abs(lastObstacleZ - nearest) > 1f && pos.y < 2.4f)
                {
                    lastObstacleZ = nearest;
                    knockdownUntil = Time.time + 1.1f;
                }
            }
            if (push && Time.time - lastPush > 2f)
            {
                lastPush = Time.time;
                var others = FindObjectsByType<Runner>(FindObjectsSortMode.None);
                foreach (var other in others)
                    if (other != this && Vector3.Distance(transform.position, other.transform.position) < 2.5f)
                        other.knockdownUntil = Time.time + 1.2f;
            }
        }
    }
}
