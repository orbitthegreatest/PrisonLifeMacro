using System;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace PrisonLifeMacro
{
    public partial class WeaponSlotPickerWindow : Window
    {
        public string ResultSlots { get; private set; }

        private readonly bool[] _active = new bool[10]; // index 1-9

        private static readonly SolidColorBrush ActiveBrush = new SolidColorBrush(Color.FromRgb(0xB0, 0x70, 0x30));
        private static readonly SolidColorBrush InactiveBrush = new SolidColorBrush(Color.FromRgb(0x26, 0x20, 0x19));
        private static readonly SolidColorBrush ActiveText = new SolidColorBrush(Color.FromRgb(0xEA, 0xE4, 0xDC));
        private static readonly SolidColorBrush InactiveText = new SolidColorBrush(Color.FromRgb(0x8F, 0x85, 0x7A));

        public WeaponSlotPickerWindow(string currentSlots)
        {
            InitializeComponent();
            foreach (var s in currentSlots.Split(','))
            {
                int n;
                if (int.TryParse(s.Trim(), out n) && n >= 1 && n <= 9)
                    _active[n] = true;
            }
            UpdateUI();
        }

        private void Slot_Click(object sender, RoutedEventArgs e)
        {
            var btn = (System.Windows.Controls.Button)sender;
            int n = int.Parse(btn.Content.ToString());
            _active[n] = !_active[n];
            UpdateUI();
        }

        private void UpdateUI()
        {
            var buttons = new[] { Slot1, Slot2, Slot3, Slot4, Slot5, Slot6, Slot7, Slot8, Slot9 };
            for (int i = 0; i < 9; i++)
            {
                int slot = i + 1;
                buttons[i].Background = _active[slot] ? ActiveBrush : InactiveBrush;
                buttons[i].Foreground = _active[slot] ? ActiveText : InactiveText;
            }

            var active = Enumerable.Range(1, 9).Where(i => _active[i]).ToList();
            SelectedText.Text = active.Count > 0
                ? "Selected: " + string.Join(", ", active)
                : "No slots selected (using defaults 1, 2, 3)";
        }

        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            var active = Enumerable.Range(1, 9).Where(i => _active[i]).ToList();
            if (active.Count == 0) active = new System.Collections.Generic.List<int> { 1, 2, 3 };
            ResultSlots = string.Join(",", active);
            DialogResult = true;
            Close();
        }

        private void BtnCancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }

        private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed) DragMove();
        }
    }
}
