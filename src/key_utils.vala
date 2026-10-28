namespace VCommander {

    public class KeyUtils : Object {
        public static uint to_latin(uint keyval, uint keycode) {
            // Function keys, arrows, Tab, Backspace, Enter, Esc are already standardized above 0xFF00
            if (keyval >= 0xFF00) {
                return keyval;
            }

            // Standard ASCII latin letters and symbols (0x20 .. 0x7E)
            if (keyval >= 0x20 && keyval <= 0x7E) {
                return Gdk.keyval_to_lower(keyval);
            }

            // Translate physical keycode with group 0 (first layout, canonical Latin)
            var display = Gdk.Display.get_default();
            if (display != null) {
                uint latin_keyval = 0;
                int effective_group = 0;
                int level = 0;
                Gdk.ModifierType consumed;

                if (display.translate_key(keycode, 0, 0, out latin_keyval, out effective_group, out level, out consumed)) {
                    if (latin_keyval > 0) {
                        return Gdk.keyval_to_lower(latin_keyval);
                    }
                }
            }

            return Gdk.keyval_to_lower(keyval);
        }
    }
}
