namespace VCommander {

    public class WallpaperService : Object {

        public static bool is_wallpaper_supported(string filename) {
            int dot = filename.last_index_of_char('.');
            if (dot < 0 || dot >= filename.length - 1) {
                return false;
            }
            string ext = filename.substring(dot + 1).down();
            return (ext == "jpg" || ext == "jpeg" || ext == "png" ||
                    ext == "webp" || ext == "bmp" || ext == "svg" ||
                    ext == "jxl" || ext == "avif" || ext == "tif" ||
                    ext == "tiff");
        }

        public static async void set_as_wallpaper(Gtk.Window parent_window, File file) {
            string uri = file.get_uri();

            // Try standard Freedesktop / GNOME Portal first (native Nautilus dialog)
            try {
                var conn = yield Bus.get(BusType.SESSION, null);
                var dict = new GLib.VariantDict(null);
                dict.insert("show-preview", "b", true);
                Variant opts = dict.end();

                yield conn.call(
                    "org.freedesktop.portal.Desktop",
                    "/org/freedesktop/portal/desktop",
                    "org.freedesktop.portal.Wallpaper",
                    "SetWallpaperURI",
                    new Variant("(ss@a{sv})", "", uri, opts),
                    null,
                    DBusCallFlags.NONE,
                    5000,
                    null
                );
                AppLogger.info("WallpaperService", @"Invoked desktop portal wallpaper dialog for: $uri");
                return;
            } catch (Error e) {
                AppLogger.warn("WallpaperService", @"Portal wallpaper failed: $(e.message). Using fallback dialog.");
            }

            // Fallback: internal Libadwaita dialog
            WallpaperDialog.show(parent_window, file);
        }
    }

    public class WallpaperDialog : Adw.Dialog {
        private static WallpaperDialog? active_dialog = null;

        private unowned Gtk.Window parent_win;
        private File image_file;

        public static void show(Gtk.Window parent_window, File file) {
            if (active_dialog != null) {
                active_dialog.present(parent_window);
                return;
            }
            var dlg = new WallpaperDialog(parent_window, file);
            dlg.present(parent_window);
        }

        private WallpaperDialog(Gtk.Window parent_window, File file) {
            Object();
            this.parent_win = parent_window;
            this.image_file = file;
            active_dialog = this;

            this.title = "Set as Wallpaper";
            this.content_width = 460;
            this.content_height = 480;

            this.closed.connect(() => {
                active_dialog = null;
            });

            var toolbar_view = new Adw.ToolbarView();

            var header_bar = new Adw.HeaderBar();
            header_bar.show_title = true;
            toolbar_view.add_top_bar(header_bar);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.propagate_natural_height = true;
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            content_box.margin_start = 16;
            content_box.margin_end = 16;
            content_box.margin_top = 16;
            content_box.margin_bottom = 16;

            // Image preview
            var picture = new Gtk.Picture.for_file(file);
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            picture.height_request = 220;
            picture.add_css_class("card");
            content_box.append(picture);

            // Options group
            var pref_group = new Adw.PreferencesGroup();
            pref_group.title = "Destination";

            var bg_row = new Adw.SwitchRow();
            bg_row.title = "Desktop Background";
            bg_row.subtitle = "Set as primary desktop wallpaper";
            bg_row.active = true;
            pref_group.add(bg_row);

            var lock_row = new Adw.SwitchRow();
            lock_row.title = "Lock Screen";
            lock_row.subtitle = "Set as lock screen wallpaper";
            lock_row.active = true;
            pref_group.add(lock_row);

            content_box.append(pref_group);
            scrolled.set_child(content_box);
            toolbar_view.set_content(scrolled);

            // Bottom action bar
            var bottom_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            bottom_bar.margin_start = 16;
            bottom_bar.margin_end = 16;
            bottom_bar.margin_top = 8;
            bottom_bar.margin_bottom = 8;

            var cancel_btn = new Gtk.Button.with_label("Cancel");
            cancel_btn.clicked.connect(() => {
                close();
            });
            bottom_bar.append(cancel_btn);

            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom_bar.append(spacer);

            var apply_btn = new Gtk.Button.with_label("Set as Wallpaper");
            apply_btn.add_css_class("suggested-action");
            apply_btn.clicked.connect(() => {
                apply_wallpaper(bg_row.active, lock_row.active);
                close();
            });
            bottom_bar.append(apply_btn);

            toolbar_view.add_bottom_bar(bottom_bar);
            set_child(toolbar_view);
        }

        private void apply_wallpaper(bool set_bg, bool set_lock) {
            string uri = image_file.get_uri();
            var schema_source = SettingsSchemaSource.get_default();

            if (set_bg && schema_source != null && schema_source.lookup("org.gnome.desktop.background", true) != null) {
                try {
                    var s = new GLib.Settings("org.gnome.desktop.background");
                    s.set_string("picture-uri", uri);
                    s.set_string("picture-uri-dark", uri);
                } catch (Error e) {
                    AppLogger.warn("WallpaperDialog", @"Failed to set background GSettings: $(e.message)");
                }
            }

            if (set_lock && schema_source != null && schema_source.lookup("org.gnome.desktop.screensaver", true) != null) {
                try {
                    var s = new GLib.Settings("org.gnome.desktop.screensaver");
                    s.set_string("picture-uri", uri);
                } catch (Error e) {
                    AppLogger.warn("WallpaperDialog", @"Failed to set screensaver GSettings: $(e.message)");
                }
            }

            var main_win = parent_win as MainWindow;
            if (main_win != null) {
                main_win.show_command_toast("Wallpaper updated successfully");
            }
        }
    }
}
