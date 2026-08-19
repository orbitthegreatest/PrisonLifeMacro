using System;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Forms;
using PrisonLifeMacro.Core;

namespace PrisonLifeMacro
{
    public partial class App : System.Windows.Application
    {
        private const string MutexName = "PrisonLifeMacro_SingleInstance";
        private const string ShowEventName = "PrisonLifeMacro_ShowEvent";

        private Mutex _mutex;
        private EventWaitHandle _showEvent;
        private Thread _showWaiter;
        private NotifyIcon _tray;
        private MainWindow _win;
        private HookManager _hooks;
        private MacroEngine _engine;
        private UpdateChecker _updater;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            try
            {
                StartupCore(e);
            }
            catch (Exception ex)
            {
                LogError("Startup", ex);
                System.Windows.Forms.MessageBox.Show("Prison Life Macro failed to start:\n\n" + ex, "Error", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
                Shutdown();
            }
        }

        private void StartupCore(StartupEventArgs e)
        {

            bool firstInstance;
            _mutex = new Mutex(true, MutexName, out firstInstance);
            if (!firstInstance)
            {
                try { EventWaitHandle.OpenExisting(ShowEventName).Set(); } catch { }
                Shutdown();
                return;
            }

            _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
            _showWaiter = new Thread(ShowWaiterLoop) { IsBackground = true, Name = "ShowEventWaiter" };
            _showWaiter.Start();

            Native.timeBeginPeriod(1);

            Settings.Load();

            _engine = new MacroEngine();
            _engine.Feedback += text => Dispatcher.BeginInvoke(new Action(() =>
            {
                FeedbackOverlay.Show(text);
                if (_tray != null)
                    _tray.ShowBalloonTip(3000, "Prison Life Macro", text, ToolTipIcon.Info);
            }));

            _hooks = new HookManager(_engine);
            _hooks.Start();

            _win = new MainWindow(_engine);
            if (!Settings.StartMinimized)
                _win.Show();
            else
                FeedbackOverlay.Show("Running minimized. Right-click the tray icon to open settings.", 2500);

            BuildTray();

            _updater = new UpdateChecker();
            _updater.Feedback += text => Dispatcher.BeginInvoke(new Action(() =>
            {
                FeedbackOverlay.Show(text, 4000);
                if (_tray != null)
                    _tray.ShowBalloonTip(5000, "Prison Life Macro - Update Available!", text, ToolTipIcon.Info);
            }));
            _updater.Start();
        }

        private static void LogError(string where, Exception ex)
        {
            try
            {
                string dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PrisonLifeMacro");
                Directory.CreateDirectory(dir);
                File.AppendAllText(System.IO.Path.Combine(dir, "error.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " [" + where + "] " + ex + "\r\n\r\n");
            }
            catch { }
        }

        private void ShowWaiterLoop()
        {
            while (true)
            {
                try { _showEvent.WaitOne(); } catch { return; }
                Dispatcher.BeginInvoke(new Action(ShowWindow));
            }
        }

        private void ShowWindow()
        {
            if (_win == null) return;
            _win.Show();
            _win.WindowState = WindowState.Normal;
            _win.Activate();
        }

        // ------------------------------------------------------------------
        // Tray
        // ------------------------------------------------------------------
        private void BuildTray()
        {
            _tray = new NotifyIcon
            {
                Icon = LoadIcon(),
                Text = "Prison Life Macro Suite v" + UpdateChecker.ScriptVersion,
                Visible = true,
            };
            var menu = new ContextMenuStrip();
            menu.Items.Add("Open Settings", null, (s, e) => ShowWindow());
            menu.Items.Add("Check for Updates...", null, (s, e) => CheckForUpdates(true));
            menu.Items.Add("Suspend/Resume All Macros", null, (s, e) => _engine.ToggleSuspendFromUi());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, (s, e) => RequestExit());
            _tray.ContextMenuStrip = menu;
            _tray.DoubleClick += (s, e) => ShowWindow();
        }

        private static Icon LoadIcon()
        {
            string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "PrisonLifeMacro.ico");
            try
            {
                return File.Exists(path) ? new Icon(path) : SystemIcons.Application;
            }
            catch
            {
                return SystemIcons.Application;
            }
        }

        public void CheckForUpdates(bool manual)
        {
            if (_updater != null)
                _updater.Check(manual);
        }

        public void RequestExit()
        {
            if (_win != null)
                _win.ExitRequested = true;
            Shutdown();
        }

        // ------------------------------------------------------------------
        // Shutdown
        // ------------------------------------------------------------------
        protected override void OnExit(ExitEventArgs e)
        {
            if (_tray != null)
            {
                _tray.Visible = false;
                _tray.Dispose();
            }
            if (_updater != null)
                _updater.Stop();
            if (_engine != null)
                _engine.Shutdown();
            if (_hooks != null)
                _hooks.Stop();
            Native.timeEndPeriod(1);
            base.OnExit(e);
        }
    }
}