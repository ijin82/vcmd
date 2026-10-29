namespace VCommander {

    public class OpenWithDialog : Object {
        private static Adw.Dialog? active_dialog = null;

        private delegate void SimpleAction();

        private class AppRow : Adw.ActionRow {
            public AppInfo app_info { get; construct set; }
            public bool is_default { get; construct set; default = false; }
            public bool is_recommended { get; construct set; default = false; }
            public string display_name { get; construct set; default = ""; }
            public string description { get; construct set; default = ""; }
            public string search_text { get; construct set; default = ""; }

            public AppRow(AppInfo app_info, bool is_default, bool is_recommended) {
                string d_name = app_info.get_display_name();
                if (d_name == null || d_name.length == 0) {
                    d_name = app_info.get_name();
                }
                if (d_name == null || d_name.length == 0) {
                    d_name = app_info.get_executable();
                }
                if (d_name == null) d_name = "";

                string desc = app_info.get_description();
                if (desc == null) desc = "";

                string exec_name = app_info.get_executable();
                if (exec_name == null) exec_name = "";

                Object(
                    app_info: app_info,
                    is_default: is_default,
                    is_recommended: is_recommended,
                    display_name: d_name,
                    description: desc,
                    search_text: "%s %s %s".printf(d_name.down(), desc.down(), exec_name.down())
                );

                this.title = Markup.escape_text(display_name);
                if (description.length > 0) {
                    this.subtitle = Markup.escape_text(description);
                }
                this.activatable = true;
                this.focusable = true;

                // Icon
                Icon? icon = app_info.get_icon();
                Gtk.Widget icon_widget;
                if (icon != null) {
                    var img = new Gtk.Image.from_gicon(icon);
                    img.pixel_size = 32;
                    icon_widget = img;
                } else {
                    var img = new Gtk.Image.from_icon_name("application-x-executable");
                    img.pixel_size = 32;
                    icon_widget = img;
                }
                icon_widget.margin_start = 4;
                icon_widget.margin_end = 8;
                add_prefix(icon_widget);

                // Badges
                if (is_default) {
                    var badge = new Gtk.Label("Default");
                    badge.add_css_class("caption");
                    badge.add_css_class("accent");
                    badge.valign = Gtk.Align.CENTER;
                    add_suffix(badge);
                } else if (is_recommended) {
                    var badge = new Gtk.Label("Recommended");
                    badge.add_css_class("caption");
                    badge.add_css_class("dim-label");
                    badge.valign = Gtk.Align.CENTER;
                    add_suffix(badge);
                }
            }
        }

        public static void show(Gtk.Window parent_window, File target_file, string? filename = null) {
            if (active_dialog != null) {
                active_dialog.present(parent_window);
                return;
            }

            // Determine content type
            string? content_type = null;
            try {
                var info = target_file.query_info(
                    FileAttribute.STANDARD_CONTENT_TYPE + "," + FileAttribute.STANDARD_FAST_CONTENT_TYPE,
                    FileQueryInfoFlags.NONE,
                    null
                );
                content_type = info.get_content_type();
            } catch (Error e) {
                // Ignore and fall back to filename guessing
            }

            if (content_type == null || content_type == "application/octet-stream") {
                bool uncertain = false;
                string test_name = (filename != null && filename.length > 0) ? filename : target_file.get_basename();
                content_type = ContentType.guess(test_name, null, out uncertain);
            }

            if (content_type == null || content_type.length == 0) {
                content_type = "application/octet-stream";
            }

            var dialog = new Adw.Dialog();
            active_dialog = dialog;
            dialog.title = "Open With";
            dialog.content_width = 560;
            dialog.content_height = 520;

            var toolbar_view = new Adw.ToolbarView();

            var header_bar = new Adw.HeaderBar();
            header_bar.show_title = true;
            toolbar_view.add_top_bar(header_bar);

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            content_box.margin_start = 14;
            content_box.margin_end = 14;
            content_box.margin_top = 8;
            content_box.margin_bottom = 8;

            // Target file info
            string display_fname = (filename != null && filename.length > 0) ? filename : target_file.get_basename();
            var title_label = new Gtk.Label(@"Open '$display_fname' with:");
            title_label.halign = Gtk.Align.START;
            title_label.add_css_class("heading");
            content_box.append(title_label);

            string type_desc = ContentType.get_description(content_type);
            var subtitle_label = new Gtk.Label(@"File type: $type_desc ($content_type)");
            subtitle_label.halign = Gtk.Align.START;
            subtitle_label.add_css_class("caption");
            subtitle_label.add_css_class("dim-label");
            content_box.append(subtitle_label);

            // Search entry
            var search_entry = new Gtk.SearchEntry();
            search_entry.placeholder_text = "Search installed applications...";
            content_box.append(search_entry);

            // Scrolled window for ListBox
            var scrolled = new Gtk.ScrolledWindow();
            scrolled.vexpand = true;
            scrolled.hexpand = true;
            scrolled.min_content_height = 260;

            var list_box = new Gtk.ListBox();
            list_box.selection_mode = Gtk.SelectionMode.SINGLE;
            list_box.add_css_class("boxed-list");
            scrolled.set_child(list_box);
            content_box.append(scrolled);

            // Checkbox: Always use
            var always_use_check = new Gtk.CheckButton.with_label("Always use this application for files of this type");
            always_use_check.margin_top = 4;
            always_use_check.tooltip_text = @"Save as default application for $content_type in ~/.config/mimeapps.list";
            content_box.append(always_use_check);

            toolbar_view.set_content(content_box);

            // Bottom bar
            var bottom_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            bottom_bar.margin_start = 14;
            bottom_bar.margin_end = 14;
            bottom_bar.margin_top = 8;
            bottom_bar.margin_bottom = 8;

            var cancel_button = new Gtk.Button.with_label("Cancel");
            bottom_bar.append(cancel_button);

            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom_bar.append(spacer);

            var open_button = new Gtk.Button.with_label("Open");
            open_button.add_css_class("suggested-action");
            bottom_bar.append(open_button);

            toolbar_view.add_bottom_bar(bottom_bar);
            dialog.set_child(toolbar_view);

            // Populate applications
            var seen_app_ids = new GenericSet<string>(str_hash, str_equal);
            AppInfo? default_app = AppInfo.get_default_for_type(content_type, false);
            string default_id = (default_app != null && default_app.get_id() != null) ? default_app.get_id() : "";

            // 1. Recommended apps
            var recommended_list = AppInfo.get_recommended_for_type(content_type);
            foreach (var app in recommended_list) {
                if (!app.should_show()) continue;
                string app_id = app.get_id() != null ? app.get_id() : app.get_executable();
                if (app_id == null || seen_app_ids.contains(app_id)) continue;
                seen_app_ids.add(app_id);

                bool is_def = (default_id.length > 0 && app_id == default_id);
                list_box.append(new AppRow(app, is_def, true));
            }

            // Fallback for type
            var fallback_list = AppInfo.get_all_for_type(content_type);
            foreach (var app in fallback_list) {
                if (!app.should_show()) continue;
                string app_id = app.get_id() != null ? app.get_id() : app.get_executable();
                if (app_id == null || seen_app_ids.contains(app_id)) continue;
                seen_app_ids.add(app_id);

                bool is_def = (default_id.length > 0 && app_id == default_id);
                list_box.append(new AppRow(app, is_def, true));
            }

            // 2. All installed apps
            var all_apps = AppInfo.get_all();
            foreach (var app in all_apps) {
                if (!app.should_show()) continue;
                string app_id = app.get_id() != null ? app.get_id() : app.get_executable();
                if (app_id == null || seen_app_ids.contains(app_id)) continue;
                seen_app_ids.add(app_id);

                bool is_def = (default_id.length > 0 && app_id == default_id);
                list_box.append(new AppRow(app, is_def, false));
            }

            // Sorter
            list_box.set_sort_func((row_a, row_b) => {
                var a = (AppRow) row_a;
                var b = (AppRow) row_b;

                // 1. Default first
                if (a.is_default && !b.is_default) return -1;
                if (!a.is_default && b.is_default) return 1;

                // 2. Recommended next
                if (a.is_recommended && !b.is_recommended) return -1;
                if (!a.is_recommended && b.is_recommended) return 1;

                // 3. Alphabetical
                return a.display_name.collate(b.display_name);
            });

            // Filter func
            list_box.set_filter_func((row) => {
                string query = search_entry.text.strip().down();
                if (query.length == 0) return true;
                var app_row = (AppRow) row;
                return app_row.search_text.contains(query);
            });

            search_entry.search_changed.connect(() => {
                list_box.invalidate_filter();
                // Select first visible row after filter
                GLib.Idle.add(() => {
                    Gtk.Widget? child = list_box.get_first_child();
                    while (child != null) {
                        var r = child as Gtk.ListBoxRow;
                        if (r != null && r.is_visible()) {
                            list_box.select_row(r);
                            break;
                        }
                        child = child.get_next_sibling();
                    }
                    return GLib.Source.REMOVE;
                });
            });

            // Action: execute open
            SimpleAction execute_open = () => {
                var selected = list_box.get_selected_row() as AppRow;
                if (selected == null) return;

                var chosen_app = selected.app_info;
                bool set_default = always_use_check.active;

                dialog.close();

                if (set_default) {
                    try {
                        chosen_app.set_as_default_for_type(content_type);
                    } catch (Error e) {
                        warning("Failed to set default app for %s: %s", content_type, e.message);
                    }
                }

                try {
                    var files = new GLib.List<File>();
                    files.append(target_file);
                    chosen_app.launch(files, null);
                } catch (Error e) {
                    warning("Failed to launch %s: %s", chosen_app.get_display_name(), e.message);
                }
            };

            // Connect activations
            list_box.row_activated.connect((row) => {
                execute_open();
            });

            search_entry.activate.connect(() => {
                execute_open();
            });

            open_button.clicked.connect(() => {
                execute_open();
            });

            cancel_button.clicked.connect(() => {
                dialog.close();
            });

            // Key controller (BUBBLE phase so buttons receive Enter/Space naturally)
            var key_ctrl = new Gtk.EventControllerKey();
            key_ctrl.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    dialog.close();
                    return Gdk.EVENT_STOP;
                }

                var focused = dialog.get_focus();
                bool list_has_focus = (focused != null && (focused == list_box || focused.is_ancestor(list_box)));

                // Tab / Shift+Tab navigation when focus is in list_box:
                // Move out of list to next/previous control instead of cycling through individual rows
                if (keyval == Gdk.Key.Tab || keyval == Gdk.Key.KP_Tab || keyval == Gdk.Key.ISO_Left_Tab) {
                    if (list_has_focus) {
                        bool is_backward = (keyval == Gdk.Key.ISO_Left_Tab) || ((state & Gdk.ModifierType.SHIFT_MASK) != 0);
                        if (is_backward) {
                            search_entry.grab_focus();
                        } else {
                            always_use_check.grab_focus();
                        }
                        return Gdk.EVENT_STOP;
                    }
                }

                // Enter / KP_Enter / ISO_Enter: only activate open when search entry or list row is focused
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.ISO_Enter) {
                    if (focused != null && focused == cancel_button) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    execute_open();
                    return Gdk.EVENT_STOP;
                }
                return Gdk.EVENT_PROPAGATE;
            });
            toolbar_view.add_controller(key_ctrl);

            dialog.closed.connect(() => {
                active_dialog = null;
            });

            dialog.present(parent_window);

            // Initial focus and selection
            GLib.Idle.add(() => {
                var first_row = list_box.get_row_at_index(0);
                if (first_row != null) {
                    list_box.select_row(first_row);
                    first_row.grab_focus();
                } else {
                    search_entry.grab_focus();
                }
                return GLib.Source.REMOVE;
            });
        }
    }
}
