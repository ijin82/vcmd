namespace VCommander {

    public class BookmarksDialog : Object {
        private static Adw.Dialog? active_dialog = null;

        private delegate void SimpleAction();

        public static void show(Gtk.Window parent_window, FilePanel target_panel) {
            if (active_dialog != null) {
                active_dialog.present(parent_window);
                return;
            }

            var config = ConfigManager.get_instance();

            var dialog = new Adw.Dialog();
            active_dialog = dialog;
            dialog.title = "Directory Bookmarks";

            int init_w = (config.bookmarks_dialog_width >= 400) ? config.bookmarks_dialog_width : 640;
            int init_h = (config.bookmarks_dialog_height >= 300) ? config.bookmarks_dialog_height : 580;
            dialog.content_width = init_w;
            dialog.content_height = init_h;

            var toolbar_view = new Adw.ToolbarView();

            // Header bar
            var header_bar = new Adw.HeaderBar();
            header_bar.show_title = true;
            toolbar_view.add_top_bar(header_bar);

            // Scrolled window with ListBox
            var scrolled = new Gtk.ScrolledWindow();
            scrolled.hexpand = true;
            scrolled.vexpand = true;

            var list_box = new Gtk.ListBox();
            list_box.selection_mode = Gtk.SelectionMode.SINGLE;
            list_box.add_css_class("boxed-list");
            list_box.margin_start = 12;
            list_box.margin_end = 12;
            list_box.margin_top = 12;
            list_box.margin_bottom = 12;

            // Direct key controller on list_box in CAPTURE phase to intercept
            // Ctrl+Up / Ctrl+Down (which GtkListBox/GtkScrolledWindow would otherwise consume)
            // as well as Tab / Shift+Tab, E, Delete
            var list_key_ctrl = new Gtk.EventControllerKey();
            list_key_ctrl.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            list_box.add_controller(list_key_ctrl);

            scrolled.set_child(list_box);
            toolbar_view.set_content(scrolled);

            // Bottom bar with Add Current and Cancel buttons
            var bottom_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            bottom_bar.margin_start = 12;
            bottom_bar.margin_end = 12;
            bottom_bar.margin_top = 8;
            bottom_bar.margin_bottom = 8;

            var add_button = new Gtk.Button.with_label("Add Current Directory");
            add_button.add_css_class("suggested-action");
            add_button.tooltip_text = "Bookmark current directory (Ctrl+A)";
            bottom_bar.append(add_button);

            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom_bar.append(spacer);

            var close_button = new Gtk.Button.with_label("Cancel");
            close_button.tooltip_text = "Close without navigating (Escape)";
            bottom_bar.append(close_button);

            toolbar_view.add_bottom_bar(bottom_bar);

            dialog.set_child(toolbar_view);

            // Helper to populate list
            SimpleAction populate_list = () => {
                // Clear existing items
                Gtk.Widget? child = list_box.get_first_child();
                while (child != null) {
                    var next = child.get_next_sibling();
                    list_box.remove(child);
                    child = next;
                }

                for (uint i = 0; i < config.bookmarks.length; i++) {
                    var bm = config.bookmarks.get(i);
                    var row = new Adw.ActionRow();
                    string custom_name = (bm.name != null) ? bm.name.strip() : "";
                    if (custom_name.length > 0) {
                        row.title = Markup.escape_text(custom_name);
                        row.subtitle = Markup.escape_text(bm.uri_or_path);
                    } else {
                        row.title = Markup.escape_text(bm.uri_or_path);
                        row.subtitle = null;
                    }
                    row.subtitle_selectable = false;
                    row.activatable = true;
                    row.focusable = true;
                    row.tooltip_text = "Enter: Open | E: Rename | Ctrl+↑/↓: Reorder | Del: Remove";

                    var icon = new Gtk.Image.from_icon_name("folder-symbolic");
                    row.add_prefix(icon);

                    list_box.append(row);
                }

                // Select and focus first row if available
                var first_row = list_box.get_row_at_index(0);
                if (first_row != null) {
                    list_box.select_row(first_row);
                    first_row.grab_focus();
                }
            };

            populate_list();

            // Navigation action
            SimpleAction activate_selected_bookmark = () => {
                var selected_row = list_box.get_selected_row();
                if (selected_row == null) return;
                int idx = selected_row.get_index();
                if (idx >= 0 && idx < (int) config.bookmarks.length) {
                    var bm = config.bookmarks.get((uint) idx);
                    string target_path = bm.uri_or_path;
                    dialog.close();

                    File target_file;
                    if (target_path.contains("://")) {
                        target_file = File.new_for_uri(target_path);
                    } else {
                        target_file = File.new_for_commandline_arg(target_path);
                    }
                    target_panel.load_directory(target_file);
                    target_panel.grab_focus_to_list();
                }
            };

            // Delete action
            SimpleAction delete_selected_bookmark = () => {
                var selected_row = list_box.get_selected_row();
                if (selected_row == null) return;
                int idx = selected_row.get_index();
                if (idx >= 0 && idx < (int) config.bookmarks.length) {
                    config.remove_bookmark((uint) idx);
                    populate_list();
                    int new_idx = int.min(idx, (int) config.bookmarks.length - 1);
                    if (new_idx >= 0) {
                        var next_row = list_box.get_row_at_index(new_idx);
                        if (next_row != null) {
                            list_box.select_row(next_row);
                            next_row.grab_focus();
                        }
                    }
                }
            };

            // Move bookmark up
            SimpleAction move_selected_bookmark_up = () => {
                var selected_row = list_box.get_selected_row();
                if (selected_row == null) return;
                int idx = selected_row.get_index();
                if (idx > 0 && idx < (int) config.bookmarks.length) {
                    if (config.move_bookmark_up((uint) idx)) {
                        populate_list();
                        var target_row = list_box.get_row_at_index(idx - 1);
                        if (target_row != null) {
                            list_box.select_row(target_row);
                            target_row.grab_focus();
                        }
                    }
                }
            };

            // Move bookmark down
            SimpleAction move_selected_bookmark_down = () => {
                var selected_row = list_box.get_selected_row();
                if (selected_row == null) return;
                int idx = selected_row.get_index();
                if (idx >= 0 && idx + 1 < (int) config.bookmarks.length) {
                    if (config.move_bookmark_down((uint) idx)) {
                        populate_list();
                        var target_row = list_box.get_row_at_index(idx + 1);
                        if (target_row != null) {
                            list_box.select_row(target_row);
                            target_row.grab_focus();
                        }
                    }
                }
            };

            // Prompt edit selected bookmark name
            SimpleAction prompt_edit_selected_bookmark = () => {
                var selected_row = list_box.get_selected_row();
                if (selected_row == null) return;
                int idx = selected_row.get_index();
                if (idx >= 0 && idx < (int) config.bookmarks.length) {
                    var bm = config.bookmarks.get((uint) idx);
                    var edit_dialog = new Adw.AlertDialog(
                        "Edit Bookmark",
                        @"Folder: $(bm.uri_or_path)\nEnter a new name, or leave blank to display full path:"
                    );
                    edit_dialog.set_prefer_wide_layout(true);
                    edit_dialog.set_content_width(520);

                    var entry = new Gtk.Entry();
                    entry.max_length = 50;
                    entry.text = bm.name != null ? bm.name : "";
                    entry.placeholder_text = "Bookmark name (optional, max 50 chars)";
                    entry.activates_default = true;
                    edit_dialog.set_extra_child(entry);

                    edit_dialog.add_response("cancel", "Cancel");
                    edit_dialog.add_response("save", "Save");
                    edit_dialog.set_default_response("save");
                    edit_dialog.set_close_response("cancel");
                    bool edit_executed = false;
                    SimpleAction do_edit_save = () => {
                        if (edit_executed) return;
                        edit_executed = true;
                        string new_name = (entry.text != null) ? entry.text.strip() : "";
                        config.update_bookmark_name((uint) idx, new_name);
                        populate_list();
                        edit_dialog.force_close();
                        var cur_row = list_box.get_row_at_index(idx);
                        if (cur_row != null) {
                            list_box.select_row(cur_row);
                            cur_row.grab_focus();
                        } else {
                            list_box.grab_focus();
                        }
                    };

                    entry.activate.connect(() => {
                        do_edit_save();
                    });

                    edit_dialog.choose.begin(dialog, null, (obj, res) => {
                        string response = edit_dialog.choose.end(res);
                        if (response == "save") {
                            do_edit_save();
                        } else {
                            var cur_row = list_box.get_row_at_index(idx);
                            if (cur_row != null) {
                                list_box.select_row(cur_row);
                                cur_row.grab_focus();
                            } else {
                                list_box.grab_focus();
                            }
                        }
                    });

                    GLib.Idle.add(() => {
                        entry.grab_focus();
                        entry.select_region(0, -1);
                        return GLib.Source.REMOVE;
                    });
                }
            };

            // Prompt add current directory
            SimpleAction prompt_add_current = () => {
                var current_page = target_panel.get_current_page();
                if (current_page == null || current_page.current_directory == null) return;

                File cur_dir = current_page.current_directory;
                string cur_path = cur_dir.get_uri_scheme() != "file" && cur_dir.get_uri_scheme() != null
                    ? cur_dir.get_uri()
                    : cur_dir.get_parse_name();

                var add_dialog = new Adw.AlertDialog(
                    "Add Bookmark",
                    @"Enter a custom title for the current folder:\n$cur_path"
                );
                add_dialog.set_prefer_wide_layout(true);
                add_dialog.set_content_width(520);

                var entry = new Gtk.Entry();
                entry.max_length = 50;
                entry.text = "";
                entry.placeholder_text = "Bookmark name (optional, max 50 chars)";
                entry.activates_default = true;
                add_dialog.set_extra_child(entry);

                add_dialog.add_response("cancel", "Cancel");
                add_dialog.add_response("add", "Add Bookmark");
                add_dialog.set_default_response("add");
                add_dialog.set_close_response("cancel");
                add_dialog.set_response_appearance("add", Adw.ResponseAppearance.SUGGESTED);

                bool add_executed = false;
                SimpleAction do_add_save = () => {
                    if (add_executed) return;
                    add_executed = true;
                    string custom_name = (entry.text != null) ? entry.text.strip() : "";
                    config.add_bookmark(custom_name, cur_path);
                    populate_list();
                    add_dialog.force_close();

                    // Select the newly added bookmark (last in list)
                    int last_idx = (int) config.bookmarks.length - 1;
                    if (last_idx >= 0) {
                        var new_row = list_box.get_row_at_index(last_idx);
                        if (new_row != null) {
                            list_box.select_row(new_row);
                            new_row.grab_focus();
                        }
                    }
                };

                entry.activate.connect(() => {
                    do_add_save();
                });

                add_dialog.choose.begin(dialog, null, (obj, res) => {
                    string response = add_dialog.choose.end(res);
                    if (response == "add") {
                        do_add_save();
                    } else {
                        var sel_row = list_box.get_selected_row();
                        if (sel_row != null) {
                            sel_row.grab_focus();
                        } else {
                            list_box.grab_focus();
                        }
                    }
                });

                GLib.Idle.add(() => {
                    entry.grab_focus();
                    entry.select_region(0, -1);
                    return GLib.Source.REMOVE;
                });
            };

            // Wire buttons
            add_button.clicked.connect(() => {
                prompt_add_current();
            });

            close_button.clicked.connect(() => {
                dialog.close();
            });

            list_box.row_activated.connect((row) => {
                activate_selected_bookmark();
            });

            // Direct list key controller (CAPTURE phase on list_box)
            // Intercepts Ctrl+Up, Ctrl+Down, Tab, Shift+Tab, E, Delete before GtkScrolledWindow or GtkListBox bindings
            list_key_ctrl.key_pressed.connect((keyval, keycode, state) => {
                uint latin_key = KeyUtils.to_latin(keyval, keycode);

                // Tab / Shift+Tab: move out of list to bottom buttons
                if (keyval == Gdk.Key.Tab || keyval == Gdk.Key.KP_Tab || keyval == Gdk.Key.ISO_Left_Tab) {
                    bool is_backward = (keyval == Gdk.Key.ISO_Left_Tab) || ((state & Gdk.ModifierType.SHIFT_MASK) != 0);
                    if (is_backward) {
                        close_button.grab_focus();
                    } else {
                        add_button.grab_focus();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Up / Ctrl+KP_Up: Move bookmark up
                if ((keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    move_selected_bookmark_up();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Down / Ctrl+KP_Down: Move bookmark down
                if ((keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    move_selected_bookmark_down();
                    return Gdk.EVENT_STOP;
                }

                // E: Edit selected bookmark name
                if ((latin_key == Gdk.Key.e || keyval == Gdk.Key.e || keyval == Gdk.Key.E) &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    prompt_edit_selected_bookmark();
                    return Gdk.EVENT_STOP;
                }

                // Delete or Shift+Delete: Delete selected bookmark
                if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.KP_Delete) {
                    delete_selected_bookmark();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+A: Add current directory (must be handled here, otherwise
                // GtkListBox's built-in select-all binding consumes it)
                if (latin_key == Gdk.Key.a &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & Gdk.ModifierType.ALT_MASK) == 0) {
                    prompt_add_current();
                    return Gdk.EVENT_STOP;
                }

                return Gdk.EVENT_PROPAGATE;
            });

            dialog.closed.connect(() => {
                active_dialog = null;
                target_panel.grab_focus_to_list();
            });

            dialog.present(parent_window);

            GLib.Idle.add(() => {
                var first_row = list_box.get_row_at_index(0);
                if (first_row != null) {
                    list_box.select_row(first_row);
                    first_row.grab_focus();
                } else {
                    list_box.grab_focus();
                }
                return GLib.Source.REMOVE;
            });
        }
    }
}
