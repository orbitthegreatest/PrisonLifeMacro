using System;
using System.IO;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// GitHub release detector - same behavior as the AHK updater: check on
    /// startup, then hourly; tray notification once per new release; manual
    /// check shows a dialog with a download link.
    /// </summary>
    public sealed class UpdateChecker
    {
        public const string ScriptVersion = "4.5.1";
        private const string Repo = "orbitthegreatest/PrisonLifeMacro";
        private const string ApiUrl = "https://api.github.com/repos/" + Repo + "/releases/latest";
        public const string ReleasesUrl = "https://github.com/" + Repo + "/releases/latest";

        private Timer _timer;

        public event Action<string> Feedback;

        public void Start()
        {
            _timer = new Timer(_ => Check(false), null, 4000, 3600000);
        }

        public void Stop()
        {
            if (_timer != null) _timer.Dispose();
        }

        public void Check(bool manual)
        {
            ThreadPool.QueueUserWorkItem(_ => DoCheck(manual));
        }

        private void DoCheck(bool manual)
        {
            string latest = null;
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(ApiUrl);
                req.Method = "GET";
                req.UserAgent = "PrisonLifeMacro-Updater";
                req.Timeout = 8000;
                req.ReadWriteTimeout = 8000;
                using (var resp = (HttpWebResponse)req.GetResponse())
                {
                    if (resp.StatusCode == HttpStatusCode.OK)
                    {
                        using (var sr = new StreamReader(resp.GetResponseStream()))
                        {
                            var m = Regex.Match(sr.ReadToEnd(), "\"tag_name\"\\s*:\\s*\"([^\"]+)\"");
                            if (m.Success)
                                latest = m.Groups[1].Value;
                        }
                    }
                }
            }
            catch { }

            if (string.IsNullOrEmpty(latest))
            {
                if (manual)
                    RaiseOnUi(() =>
                        System.Windows.MessageBox.Show("Couldn't reach GitHub to check for updates.\nCheck your internet connection and try again.",
                            "Update Check", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning));
                return;
            }

            string latestNum = Regex.Replace(latest, "^[^0-9]+", "");
            if (CompareVersions(latestNum, ScriptVersion) <= 0)
            {
                if (manual)
                    RaiseOnUi(() =>
                        System.Windows.MessageBox.Show("You're up to date!\n\nCurrent version : " + ScriptVersion + "\nLatest release : " + latest,
                            "Update Check", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Information));
                return;
            }

            // New release - notify once per release.
            bool isNew = Settings.UpdateLastNotified != latest;
            if (isNew)
            {
                Settings.UpdateLastNotified = latest;
                Settings.Save();
                RaiseOnUi(() =>
                {
                    var f = Feedback;
                    if (f != null) f("New version " + latest + " is out!  Download: " + ReleasesUrl);
                });
            }

            if (manual)
            {
                RaiseOnUi(() =>
                {
                    var r = System.Windows.MessageBox.Show(
                        "A new version of Prison Life Macro is available!\n\n" +
                        "Current version : " + ScriptVersion + "\nLatest release : " + latest + "\n\nOpen the download page?",
                        "Update Available", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Information);
                    if (r == System.Windows.MessageBoxResult.Yes)
                        System.Diagnostics.Process.Start(ReleasesUrl);
                });
            }
        }

        private void RaiseOnUi(Action a)
        {
            var app = System.Windows.Application.Current;
            if (app != null)
            {
                app.Dispatcher.BeginInvoke(a);
            }
            else
            {
                a();
            }
        }

        private static int CompareVersions(string v1, string v2)
        {
            var p1 = v1.Split('.');
            var p2 = v2.Split('.');
            int n = Math.Max(p1.Length, p2.Length);
            for (int i = 0; i < n; i++)
            {
                int a = i < p1.Length ? ParseInt(p1[i]) : 0;
                int b = i < p2.Length ? ParseInt(p2[i]) : 0;
                if (a > b) return 1;
                if (a < b) return -1;
            }
            return 0;
        }

        private static int ParseInt(string s)
        {
            int v;
            return int.TryParse(s, out v) ? v : 0;
        }
    }
}