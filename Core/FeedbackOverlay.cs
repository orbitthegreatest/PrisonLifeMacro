using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Small topmost "tooltip" overlay shown near the cursor (replaces the
    /// AHK ToolTip feedback): rounded dark card, accent text, fade in/out.
    /// </summary>
    public sealed class FeedbackOverlay : Window
    {
        private static FeedbackOverlay _instance;
        private readonly Border _card;
        private readonly TextBlock _text;
        private readonly DispatcherTimer _timer;

        public static void Show(string text, int ms = 2000)
        {
            if (_instance == null)
                _instance = new FeedbackOverlay();
            _instance.Display(text, ms);
        }

        private FeedbackOverlay()
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            ResizeMode = ResizeMode.NoResize;
            Topmost = true;
            ShowActivated = false;
            IsHitTestVisible = false;
            Width = 520;
            Height = 120;

            _card = new Border
            {
                CornerRadius = new CornerRadius(12),
                Background = new SolidColorBrush(Color.FromRgb(0x24, 0x1D, 0x15)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0x4A, 0x39, 0x22)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(16, 10, 16, 10),
            };
            _text = new TextBlock
            {
                Foreground = new SolidColorBrush(Color.FromRgb(0xEA, 0xE4, 0xDC)),
                FontSize = 13,
                FontFamily = new FontFamily("Segoe UI"),
                TextWrapping = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center,
            };
            _card.Child = _text;
            Content = _card;

            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            _timer.Tick += (s, e) => FadeOut();
        }

        private void Display(string text, int ms)
        {
            _timer.Stop();
            _text.Text = text;

            // Resize to content, then position above/near the cursor.
            var size = MeasureString(text);
            double w = Math.Min(520, size.Width + 40);
            double h = Math.Min(120, size.Height + 34);
            Width = w;
            Height = h;

            var pt = System.Windows.Forms.Cursor.Position;
            Left = Math.Max(4, pt.X - (int)w / 2);
            double top = pt.Y + 24;
            if (top + h > SystemParameters.WorkArea.Bottom)
                top = pt.Y - h - 16;
            Top = Math.Max(4, top);

            if (!IsVisible)
            {
                Show();
                BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(140)));
            }
            else
            {
                BeginAnimation(OpacityProperty, new DoubleAnimation(Opacity, 1, TimeSpan.FromMilliseconds(100)));
            }
            _timer.Interval = TimeSpan.FromMilliseconds(Math.Max(600, ms));
            _timer.Start();
        }

        private Size MeasureString(string text)
        {
            var tb = new TextBlock
            {
                Text = text,
                FontSize = 13,
                FontFamily = new FontFamily("Segoe UI"),
                TextWrapping = TextWrapping.Wrap,
                Width = 480,
            };
            tb.Measure(new Size(480, double.PositiveInfinity));
            return tb.DesiredSize;
        }

        private void FadeOut()
        {
            _timer.Stop();
            var anim = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(220));
            anim.Completed += (s, e) => Hide();
            BeginAnimation(OpacityProperty, anim);
        }
    }
}