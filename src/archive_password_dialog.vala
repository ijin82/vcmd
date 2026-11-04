namespace VCommander {

    public class ArchivePasswordDialog : Object {
        private static bool is_active = false;

        public static async string? prompt_async(Gtk.Widget? parent, string archive_name, bool is_retry = false) {
            if (is_active) {
                return null;
            }
            is_active = true;

            var dialog = new Adw.AlertDialog(
                "Password Required",
                is_retry
                    ? @"The entered password for '$(archive_name)' was incorrect. Please try again."
                    : @"The archive '$(archive_name)' is encrypted. Please enter the password to access its contents."
            );

            dialog.add_response("cancel", "Cancel");
            dialog.add_response("unlock", "Unlock");
            dialog.set_response_appearance("unlock", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_default_response("unlock");
            dialog.set_close_response("cancel");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_start = 12;
            box.margin_end = 12;
            box.margin_top = 8;
            box.margin_bottom = 8;

            var entry = new Gtk.PasswordEntry();
            entry.show_peek_icon = true;
            entry.hexpand = true;
            entry.placeholder_text = "Password";
            entry.activate.connect(() => {
                dialog.response("unlock");
                dialog.force_close();
            });

            box.append(entry);
            dialog.set_extra_child(box);
            dialog.set_focus(entry);

            string response = yield dialog.choose(parent, null);
            dialog.force_close();

            is_active = false;

            if (response == "unlock") {
                return entry.text;
            }
            return null;
        }
    }
}
