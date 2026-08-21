using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using PrisonLifeMacro.Core;

namespace PrisonLifeMacro
{
    public partial class MainWindow : Window
    {
        private readonly MacroEngine _engine;

        public bool ExitRequested;

        public MainWindow(MacroEngine engine)
        {
            _engine = engine;
            InitializeComponent();
            RootGrid.Clip = new RectangleGeometry(new Rect(0, 0, Width, Height), 24, 24);
            LoadLogo();
            PopulateFromSettings();
            WireAnimations();
            WireEngineEvents();
        }

        // ------------------------------------------------------------------
        // Logo + version
        // ------------------------------------------------------------------
        private void LoadLogo()
        {
            try
            {
                var asm = typeof(MainWindow).Assembly;
                foreach (var name in asm.GetManifestResourceNames())
                {
                    if (!name.EndsWith("PrisonLifeMacro.ico", StringComparison.OrdinalIgnoreCase))
                        continue;
                    using (var s = asm.GetManifestResourceStream(name))
                    {
                        var decoder = new IconBitmapDecoder(s, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                        var frame = decoder.Frames[0];
                        frame.Freeze();
                        LogoImage.Source = frame;
                    }
                    break;
                }
            }
            catch { }
            VersionText.Text = "v" + UpdateChecker.ScriptVersion;
        }

        private void PopulateFromSettings()
        {
            CSInput.Text = Settings.CS.ToString("0.######");
            DPIInput.Text = Settings.DPI.ToString("0.####");
            FPSInput.Text = Settings.FPS.ToString("0.####");
            GunSlotCountInput.Text = Settings.GunSlotCount.ToString();
            StartMinCB.IsChecked = Settings.StartMinimized;

            PJEnabledCB.IsChecked = Settings.PressureJumpEnabled;
            PJHotkeyDisplay.Text = KeyDisplay(Settings.PressureJumpKey);

            FreezeEnabledCB.IsChecked = Settings.FreezeEnabled;
            FreezeHotkeyDisplay.Text = KeyDisplay(Settings.FreezeKey);
            FreezeModeToggle.IsChecked = Settings.FreezeMode == "Toggle";
            FreezeModeHold.IsChecked = Settings.FreezeMode == "Hold";

            RotEnabledCB.IsChecked = Settings.RotationEnabled;
            RotHotkeyDisplay.Text = KeyDisplay(Settings.RotationKey);

            SprEnabledCB.IsChecked = Settings.SprintEnabled;

            IncSlotHotkeyDisplay.Text = KeyDisplay(Settings.IncreaseSlotKey);
            DecSlotHotkeyDisplay.Text = KeyDisplay(Settings.DecreaseSlotKey);

            GSuspendHotkeyDisplay.Text = KeyDisplay(Settings.GlobalSuspendKey);

            FGSEnabledCB.IsChecked = Settings.FastGunSwapEnabled;
            FGSHotkeyDisplay.Text = KeyDisplay(Settings.FastGunSwapKey);
            FGSOnOffHotkeyDisplay.Text = KeyDisplay(Settings.FastGunSwapOnOffKey);
            FGSModeHold.IsChecked = Settings.FastGunSwapMode == "Hold";
            FGSModeToggle.IsChecked = Settings.FastGunSwapMode == "Toggle";

            SREnabledCB.IsChecked = Settings.ShuffleReloadEnabled;
            SRHotkeyDisplay.Text = KeyDisplay(Settings.ShuffleReloadKey);
        }

        private static string KeyDisplay(string k)
        {
            return string.IsNullOrEmpty(k) ? "(none)" : k;
        }

        // ------------------------------------------------------------------
        // Animations
        // ------------------------------------------------------------------
        private void WireAnimations()
        {
            // Window fade/scale-in
            BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(260)));
            var scaleIn = new ScaleTransform(0.96, 0.96);
            RootBorder.RenderTransform = scaleIn;
            RootBorder.RenderTransformOrigin = new Point(0.5, 0.5);
            var sx = new DoubleAnimation(0.96, 1.0, TimeSpan.FromMilliseconds(320)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            var sy = new DoubleAnimation(0.96, 1.0, TimeSpan.FromMilliseconds(320)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            scaleIn.BeginAnimation(ScaleTransform.ScaleXProperty, sx);
            scaleIn.BeginAnimation(ScaleTransform.ScaleYProperty, sy);

            // Logo glow pulse
            var glowPulse = new DoubleAnimation(0.3, 0.75, TimeSpan.FromSeconds(1.6))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
            };
            LogoGlow.BeginAnimation(DropShadowEffect.OpacityProperty, glowPulse);

            // Accent shimmer sweep
            var shimmer = new DoubleAnimation(-260, 790, TimeSpan.FromSeconds(3.2))
            {
                RepeatBehavior = RepeatBehavior.Forever,
            };
            ShimmerT.BeginAnimation(TranslateTransform.XProperty, shimmer);

            // Dots idle pulse
            var pulse = new DoubleAnimation(1.0, 1.08, TimeSpan.FromSeconds(1.15))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
            };
            DotMinScale.BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
            DotMinScale.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
            var pulse2 = new DoubleAnimation(1.0, 1.08, TimeSpan.FromSeconds(1.15))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                BeginTime = TimeSpan.FromMilliseconds(300),
            };
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleXProperty, pulse2);
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleYProperty, pulse2);

            // Buttons: hover color shift + press squash
            AttachButtonHover(BtnSave, Color.FromRgb(0xB0, 0x70, 0x30), Color.FromRgb(0xD4, 0x8A, 0x40));
            AttachButtonHover(BtnHide, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(BtnCheckUpdates, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(BtnAboutUpdates, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(PJSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(FreezeSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(RotSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(FGSSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(FGSOnOffSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(SRSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(IncSlotSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(DecSlotSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
            AttachButtonHover(GSuspendSetBtn, Color.FromRgb(0x26, 0x20, 0x19), Color.FromRgb(0x33, 0x2A, 0x1F));
        }

        private void AttachButtonHover(Button b, Color baseColor, Color hoverColor)
        {
            var brush = new SolidColorBrush(baseColor);
            b.Background = brush;
            b.RenderTransformOrigin = new Point(0.5, 0.5);

            b.MouseEnter += (s, e) =>
            {
                brush.BeginAnimation(SolidColorBrush.ColorProperty,
                    new ColorAnimation(baseColor, hoverColor, TimeSpan.FromMilliseconds(160)));
                var st = b.RenderTransform as ScaleTransform;
                if (st == null) { st = new ScaleTransform(1, 1); b.RenderTransform = st; }
                st.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.0, 1.04, TimeSpan.FromMilliseconds(140)));
                st.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.0, 1.04, TimeSpan.FromMilliseconds(140)));
            };
            b.MouseLeave += (s, e) =>
            {
                brush.BeginAnimation(SolidColorBrush.ColorProperty,
                    new ColorAnimation(hoverColor, baseColor, TimeSpan.FromMilliseconds(180)));
                var st = b.RenderTransform as ScaleTransform;
                if (st != null)
                {
                    st.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.04, 1.0, TimeSpan.FromMilliseconds(160)));
                    st.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.04, 1.0, TimeSpan.FromMilliseconds(160)));
                }
            };
            b.PreviewMouseLeftButtonDown += (s, e) =>
            {
                var st = b.RenderTransform as ScaleTransform;
                if (st != null)
                {
                    st.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.0, 0.96, TimeSpan.FromMilliseconds(70)));
                    st.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.0, 0.96, TimeSpan.FromMilliseconds(70)));
                }
            };
        }

        private void WireEngineEvents()
        {
            _engine.Feedback += text =>
            {
                Dispatcher.BeginInvoke(new Action(() => FeedbackOverlay.Show(text)));
            };
            _engine.Captured += name =>
            {
                Dispatcher.BeginInvoke(new Action(() => OnCaptured(name)));
            };
        }

        // ------------------------------------------------------------------
        // Capture flow
        // ------------------------------------------------------------------
        private string _captureButtonText;
        private Button _captureButton;

        private void StartCapture(string target, Button button, string defaultText)
        {
            _captureButton = button;
            _captureButtonText = defaultText;
            button.Content = "Press a key or click a mouse button... (Esc cancels)";
            _engine.BeginCapture(target);
        }

        private void OnCaptured(string name)
        {
            string target = _engine.CaptureTarget;
            _engine.CaptureTarget = "";
            if (_captureButton != null)
            {
                _captureButton.Content = _captureButtonText;
                _captureButton = null;
            }

            if (name == null)
            {
                RefreshDisplays();   // canceled: restore old values
                return;
            }

            switch (target)
            {
                case "PJ": Settings.PressureJumpKey = name; break;
                case "Freeze": Settings.FreezeKey = name; break;
                case "Rotation": Settings.RotationKey = name; break;
                case "FGS": Settings.FastGunSwapKey = name; break;
                case "FGSOnOff": Settings.FastGunSwapOnOffKey = name; break;
                case "SR": Settings.ShuffleReloadKey = name; break;
                case "IncSlot": Settings.IncreaseSlotKey = name; break;
                case "DecSlot": Settings.DecreaseSlotKey = name; break;
                case "GSuspend": Settings.GlobalSuspendKey = name; break;
            }
            RefreshDisplays();
        }

        private void RefreshDisplays()
        {
            PJHotkeyDisplay.Text = KeyDisplay(Settings.PressureJumpKey);
            FreezeHotkeyDisplay.Text = KeyDisplay(Settings.FreezeKey);
            RotHotkeyDisplay.Text = KeyDisplay(Settings.RotationKey);
            FGSHotkeyDisplay.Text = KeyDisplay(Settings.FastGunSwapKey);
            FGSOnOffHotkeyDisplay.Text = KeyDisplay(Settings.FastGunSwapOnOffKey);
            SRHotkeyDisplay.Text = KeyDisplay(Settings.ShuffleReloadKey);
            IncSlotHotkeyDisplay.Text = KeyDisplay(Settings.IncreaseSlotKey);
            DecSlotHotkeyDisplay.Text = KeyDisplay(Settings.DecreaseSlotKey);
            GSuspendHotkeyDisplay.Text = KeyDisplay(Settings.GlobalSuspendKey);
        }

        // ------------------------------------------------------------------
        // Capture buttons
        // ------------------------------------------------------------------
        private void PJSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("PJ", PJSetBtn, "Click, then press key/button for Pressure Jump...");
        private void FreezeSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("Freeze", FreezeSetBtn, "Click, then press key/button for Freeze...");
        private void RotSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("Rotation", RotSetBtn, "Click, then press key/button for Rotation...");
        private void FGSSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("FGS", FGSSetBtn, "Click, then press key/button for Fast Gun Swap Trigger...");
        private void FGSOnOffSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("FGSOnOff", FGSOnOffSetBtn, "Click, then press key/button for Fast Gun Swap On/Off...");
        private void SRSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("SR", SRSetBtn, "Click, then press key/button for Shuffle Reload Trigger...");
        private void IncSlotSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("IncSlot", IncSlotSetBtn, "Click, then press key/button for Increase...");
        private void DecSlotSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("DecSlot", DecSlotSetBtn, "Click, then press key/button for Decrease...");
        private void GSuspendSetBtn_Click(object s, RoutedEventArgs e) => StartCapture("GSuspend", GSuspendSetBtn, "Click, then press key/button for Suspend...");

        // ------------------------------------------------------------------
        // Save
        // ------------------------------------------------------------------
        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            double dpi, cs, fps;
            if (!double.TryParse(DPIInput.Text.Trim().Replace(',', '.'), out dpi) || dpi <= 0 ||
                !double.TryParse(CSInput.Text.Trim().Replace(',', '.'), out cs) || cs <= 0 ||
                !double.TryParse(FPSInput.Text.Trim().Replace(',', '.'), out fps) || fps <= 0)
            {
                MessageBox.Show(this, "Please enter valid non-zero numbers for Roblox Sensitivity, Mouse DPI, and Roblox FPS.",
                    "Invalid Input", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            int slots;
            if (!int.TryParse(GunSlotCountInput.Text.Trim(), out slots) || slots < 1 || slots > 10)
            {
                MessageBox.Show(this, "Gun Slots must be a whole number between 1 and 10.",
                    "Invalid Input", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            Settings.DPI = dpi;
            Settings.CS = cs;
            Settings.FPS = fps;
            Settings.GunSlotCount = slots;
            Settings.PressureJumpEnabled = PJEnabledCB.IsChecked == true;
            Settings.FreezeEnabled = FreezeEnabledCB.IsChecked == true;
            Settings.FreezeMode = FreezeModeHold.IsChecked == true ? "Hold" : "Toggle";
            Settings.RotationEnabled = RotEnabledCB.IsChecked == true;
            Settings.SprintEnabled = SprEnabledCB.IsChecked == true;
            Settings.FastGunSwapEnabled = FGSEnabledCB.IsChecked == true;
            Settings.FastGunSwapMode = FGSModeToggle.IsChecked == true ? "Toggle" : "Hold";
            Settings.ShuffleReloadEnabled = SREnabledCB.IsChecked == true;
            Settings.StartMinimized = StartMinCB.IsChecked == true;

            _engine.RecalculatePixels();
            Settings.Save();

            string warnings = "";
            if (Settings.PressureJumpEnabled && string.IsNullOrEmpty(Settings.PressureJumpKey))
                warnings += "- Pressure Jump is enabled but has no keybind set.\n";
            if (Settings.FreezeEnabled && string.IsNullOrEmpty(Settings.FreezeKey))
                warnings += "- Freeze is enabled but has no keybind set.\n";
            if (Settings.RotationEnabled && string.IsNullOrEmpty(Settings.RotationKey))
                warnings += "- Rotation is enabled but has no keybind set.\n";
            if (Settings.FastGunSwapEnabled && string.IsNullOrEmpty(Settings.FastGunSwapKey))
                warnings += "- Fast Gun Swap is enabled but has no trigger keybind set.\n";
            if (Settings.ShuffleReloadEnabled && string.IsNullOrEmpty(Settings.ShuffleReloadKey))
                warnings += "- Shuffle Reload is enabled but has no trigger keybind set.\n";
            if (warnings.Length > 0)
                MessageBox.Show(this, warnings + "\nThose macros won't trigger until you set a keybind on their tab.",
                    "No Keybind Set", MessageBoxButton.OK, MessageBoxImage.Warning);

            FeedbackOverlay.Show("Settings saved");
        }

        private void BtnHide_Click(object sender, RoutedEventArgs e)
        {
            Hide();
        }

        private void BtnAboutUpdates_Click(object sender, RoutedEventArgs e)
        {
            ((App)Application.Current).CheckForUpdates(true);
        }

        // ------------------------------------------------------------------
        // Header drag + window dots
        // ------------------------------------------------------------------
        private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed)
                DragMove();
        }

        private void DotMin_MouseEnter(object sender, MouseEventArgs e)
        {
            DotMinScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.0, 1.24, TimeSpan.FromMilliseconds(150)));
            DotMinScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.0, 1.24, TimeSpan.FromMilliseconds(150)));
            DotMinGlow.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(0, 0.95, TimeSpan.FromMilliseconds(180)));
        }

        private void DotMin_MouseLeave(object sender, MouseEventArgs e)
        {
            var pulse = new DoubleAnimation(1.0, 1.08, TimeSpan.FromSeconds(1.15)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever };
            DotMinScale.BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
            DotMinScale.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
            DotMinGlow.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(0.95, 0, TimeSpan.FromMilliseconds(220)));
        }

        private void DotClose_MouseEnter(object sender, MouseEventArgs e)
        {
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.0, 1.24, TimeSpan.FromMilliseconds(150)));
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.0, 1.24, TimeSpan.FromMilliseconds(150)));
            DotCloseGlow.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(0, 0.95, TimeSpan.FromMilliseconds(180)));
        }

        private void DotClose_MouseLeave(object sender, MouseEventArgs e)
        {
            var pulse = new DoubleAnimation(1.0, 1.08, TimeSpan.FromSeconds(1.15)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, BeginTime = TimeSpan.FromMilliseconds(300) };
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
            DotCloseGlow.BeginAnimation(DropShadowEffect.OpacityProperty, new DoubleAnimation(0.95, 0, TimeSpan.FromMilliseconds(220)));
        }

        private void DotMin_Click(object sender, MouseButtonEventArgs e)
        {
            DotMinScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.0, 0.82, TimeSpan.FromMilliseconds(90)));
            DotMinScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.0, 0.82, TimeSpan.FromMilliseconds(90)));
            WindowState = WindowState.Minimized;          // yellow: minimize to taskbar
        }

        private void DotClose_Click(object sender, MouseButtonEventArgs e)
        {
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1.0, 0.82, TimeSpan.FromMilliseconds(90)));
            DotCloseScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1.0, 0.82, TimeSpan.FromMilliseconds(90)));
            Hide();                                        // red: minimize to tray
        }

        protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
        {
            if (!ExitRequested)
            {
                e.Cancel = true;
                Hide();
                return;
            }
            base.OnClosing(e);
        }
    }
}