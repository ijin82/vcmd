namespace VCommander {

    public class MainWindow : Adw.ApplicationWindow {
        private Gtk.Paned paned;
        public FilePanel left_panel { get; private set; }
        public FilePanel right_panel { get; private set; }
        public FilePanel active_panel { get; private set; }

        private Adw.HeaderBar header_bar;
        private Gtk.Entry cmd_entry;
        private Gtk.Box fn_bar;
        private GenericArray<string> command_history;
        private int history_index = -1;
        private string saved_input = "";
        private Gtk.CssProvider font_css_provider;
        private bool escape_sequence_pending = false;
        private uint escape_sequence_timeout_id = 0;

        public MainWindow(Gtk.Application app) {
            Object(application: app, title: "Vala Commander");

            var config = ConfigManager.get_instance();
            set_default_size(config.window_width, config.window_height);
            if (config.is_maximized) {
                maximize();
            }

            command_history = new GenericArray<string>();

            load_css_styles();
            build_ui();

            // Restore active panel
            if (config.active_pane == "right") {
                activate_panel(right_panel);
            } else {
                activate_panel(left_panel);
            }

            close_request.connect(on_close_requested);

            // Ensure config exists on first run
            Timeout.add_seconds(1, () => {
                save_state();
                return false;
            });
        }

        private const string DEFAULT_STYLE_CSS = """
/* Vala Commander (vcmd) Styles */

.file-panel {
    border: 1px solid alpha(@borders, 0.4);
    border-radius: 8px;
    margin: 4px;
    transition: border-color 200ms ease, box-shadow 200ms ease;
    background-color: @view_bg_color;
}

.file-panel.active-panel {
    /* Subtle border styling: cursor in file list indicates active panel */
}

.file-panel.panel-inactive {
    border-color: alpha(@borders, 0.25);
}

.file-panel tabbar {
    border-bottom: 1px solid alpha(@borders, 0.3);
    background-color: alpha(@headerbar_bg_color, 0.4);
}

.panel-header {
    padding: 6px 8px;
    background-color: alpha(@headerbar_bg_color, 0.6);
    border-bottom: 1px solid alpha(@borders, 0.3);
}

.active-panel .panel-header {
    background-color: alpha(@headerbar_bg_color, 0.85);
}

.filter-box {
    padding: 4px 8px;
    background-color: alpha(@headerbar_bg_color, 0.75);
    border-bottom: 1px solid alpha(@borders, 0.3);
}

.active-panel .filter-box {
    background-color: alpha(@headerbar_bg_color, 0.95);
    border-bottom: 1px solid alpha(@accent_color, 0.4);
}

.panel-status-bar {
    padding: 4px 8px;
    font-size: 0.85em;
    color: @secondary_color;
    border-top: 1px solid alpha(@borders, 0.2);
    background-color: alpha(@headerbar_bg_color, 0.4);
}

.file-list-view {
    font-family: monospace;
}

.file-item-parent {
    font-weight: bold;
    color: @accent_color;
}

.file-item-dir {
    font-weight: bold;
}

.file-item-symlink {
    color: #26a269;
    font-style: italic;
}

:selected .file-item-symlink {
    color: inherit;
}

.command-bar {
    padding: 0;
}

.command-entry {
    font-family: monospace;
}

.brief-item-box {
    padding: 3px 8px;
    border-radius: 4px;
    min-width: 170px;
}

columnview,
columnview *,
gridview,
gridview *,
listview,
listview *,
row,
row * {
    transition: none;
    animation: none;
}

.function-bar {
    padding: 3px 4px 4px 4px;
    background-color: alpha(@headerbar_bg_color, 0.5);
    border-top: 1px solid alpha(@borders, 0.25);
}

.fn-button {
    padding: 3px 6px;
    border-radius: 4px;
    border: 1px solid alpha(@borders, 0.3);
    background-color: alpha(@headerbar_bg_color, 0.4);
    transition: background-color 150ms ease, border-color 150ms ease;
}

.fn-button:hover {
    background-color: alpha(@accent_color, 0.15);
    border-color: alpha(@accent_color, 0.4);
}

.fn-button:active {
    background-color: alpha(@accent_color, 0.3);
}

.fn-key-badge {
    font-weight: bold;
    color: @accent_color;
    font-size: 0.82em;
}

.fn-key-label {
    font-size: 0.82em;
}

.file-item-tagged {
    color: #c67c00;
    font-weight: bold;
}

@media (prefers-color-scheme: dark) {
    .file-item-tagged {
        color: #f6d32d;
        font-weight: bold;
    }
}

.file-item-symlink.file-item-tagged {
    color: #c67c00;
    font-weight: bold;
}

@media (prefers-color-scheme: dark) {
    .file-item-symlink.file-item-tagged {
        color: #f6d32d;
        font-weight: bold;
    }
}

:selected .file-item-tagged,
row:selected .file-item-tagged {
    color: #f8e45c;
    font-weight: bold;
}
""";

        private void load_css_styles() {
            var provider = new Gtk.CssProvider();
            provider.load_from_string(DEFAULT_STYLE_CSS);

            // Optional external style overrides
            string[] search_paths = {
                Path.build_filename(Environment.get_user_data_dir(), "vcmd", "style.css"),
                "data/style.css"
            };

            foreach (var path in search_paths) {
                var file = File.new_for_path(path);
                if (file.query_exists()) {
                    provider.load_from_file(file);
                    break;
                }
            }

            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            font_css_provider = new Gtk.CssProvider();
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                font_css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10
            );
            apply_font_styles();
        }

        public void apply_font_styles() {
            var config = ConfigManager.get_instance();
            string css = @".file-list-view { font-family: '$(config.panel_font_name)', monospace; font-size: $(config.panel_font_size)pt; }";
            font_css_provider.load_from_string(css);
        }

        private void build_ui() {
            var config = ConfigManager.get_instance();
            var root_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            // Header Bar
            header_bar = new Adw.HeaderBar();
            var title_label = new Gtk.Label("Vala Commander");
            title_label.add_css_class("title");
            header_bar.title_widget = title_label;

            var preferences_button = new Gtk.Button.from_icon_name("emblem-system-symbolic");
            preferences_button.tooltip_text = "Preferences (Ctrl+,)";
            preferences_button.clicked.connect(() => {
                prompt_preferences_dialog();
            });
            header_bar.pack_end(preferences_button);

            var help_button = new Gtk.Button.from_icon_name("help-about-symbolic");
            help_button.tooltip_text = "Keyboard Shortcuts & Controls (F1)";
            help_button.clicked.connect(() => {
                ShortcutsDialog.show(this);
            });
            header_bar.pack_end(help_button);

            root_box.append(header_bar);

            // Dual Panes
            paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            paned.hexpand = true;
            paned.vexpand = true;
            paned.wide_handle = true;

            left_panel = new FilePanel(config.left_tabs, config.left_tab_titles, config.left_active_tab, config.left_brief_view, config.left_show_hidden);
            right_panel = new FilePanel(config.right_tabs, config.right_tab_titles, config.right_active_tab, config.right_brief_view, config.right_show_hidden);

            left_panel.panel_activated.connect(on_panel_activated);
            right_panel.panel_activated.connect(on_panel_activated);

            left_panel.directory_changed.connect(on_panel_directory_changed);
            right_panel.directory_changed.connect(on_panel_directory_changed);

            left_panel.command_char_typed.connect(on_command_char_typed);
            right_panel.command_char_typed.connect(on_command_char_typed);

            left_panel.error_occurred.connect(show_error_dialog);
            right_panel.error_occurred.connect(show_error_dialog);

            left_panel.columns_layout_changed.connect((origin) => {
                var cur_page = origin.get_current_page();
                origin.update_columns_layout(cur_page);
                right_panel.update_columns_layout();
            });
            right_panel.columns_layout_changed.connect((origin) => {
                var cur_page = origin.get_current_page();
                origin.update_columns_layout(cur_page);
                left_panel.update_columns_layout();
            });

            paned.start_child = left_panel;
            paned.end_child = right_panel;
            paned.position = config.paned_position > 0 ? config.paned_position : 512;

            root_box.append(paned);

            // Bottom MC-style Command Line Bar
            build_command_bar(root_box);

            // Bottom MC-style Function Key Bar
            build_function_bar(root_box);

            content = root_box;

            setup_keyboard_shortcuts(root_box);
        }

        private void build_command_bar(Gtk.Box parent_box) {
            var command_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            command_bar.add_css_class("command-bar");
            command_bar.margin_top = 5;
            command_bar.margin_start = 4;
            command_bar.margin_end = 4;
            command_bar.margin_bottom = 4;

            cmd_entry = new Gtk.Entry();
            cmd_entry.hexpand = true;
            cmd_entry.add_css_class("command-entry");
            cmd_entry.placeholder_text = "Bash command... (Enter to run in active pane, Esc to cancel)";

            cmd_entry.activate.connect(on_command_entered);

            var entry_key_controller = new Gtk.EventControllerKey();
            entry_key_controller.key_pressed.connect(on_command_entry_key_pressed);
            cmd_entry.add_controller(entry_key_controller);

            command_bar.append(cmd_entry);
            parent_box.append(command_bar);
        }

        private void build_function_bar(Gtk.Box parent_box) {
            var config = ConfigManager.get_instance();
            fn_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            fn_bar.add_css_class("function-bar");
            fn_bar.visible = config.show_function_bar;

            fn_bar.append(create_fn_button("1", "Help", () => { ShortcutsDialog.show(this); }));
            fn_bar.append(create_fn_button("3", "View", () => {
                show_error_dialog("File Viewer", "File Viewer (F3) will be available in Stage 4.");
            }));
            fn_bar.append(create_fn_button("4", "Edit", () => {
                show_error_dialog("File Editor", "File Editor (F4) will be available in Stage 4.");
            }));
            fn_bar.append(create_fn_button("5", "Copy", () => { on_f5_copy(); }));
            fn_bar.append(create_fn_button("6", "Move", () => { on_f6_move(); }));
            fn_bar.append(create_fn_button("7", "Mkdir", () => { on_f7_mkdir(); }));
            fn_bar.append(create_fn_button("8", "Delete", () => { on_delete(false); }));
            fn_bar.append(create_fn_button("10", "Quit", () => { close(); }));

            parent_box.append(fn_bar);
        }

        private delegate void FnAction();

        private Gtk.Button create_fn_button(string key_num, string label_text, owned FnAction action) {
            var btn = new Gtk.Button();
            btn.add_css_class("fn-button");
            btn.hexpand = true;

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            box.halign = Gtk.Align.CENTER;

            var badge = new Gtk.Label(key_num);
            badge.add_css_class("fn-key-badge");

            var lbl = new Gtk.Label(label_text);
            lbl.add_css_class("fn-key-label");

            box.append(badge);
            box.append(lbl);
            btn.child = box;

            btn.clicked.connect(() => {
                action();
            });

            return btn;
        }

        private void setup_keyboard_shortcuts(Gtk.Widget target_widget) {
            var key_controller = new Gtk.EventControllerKey();
            key_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                uint latin_key = KeyUtils.to_latin(keyval, keycode);

                // Handle pending Escape sequence (e.g. Esc > i)
                if (escape_sequence_pending) {
                    escape_sequence_pending = false;
                    if (escape_sequence_timeout_id != 0) {
                        Source.remove(escape_sequence_timeout_id);
                        escape_sequence_timeout_id = 0;
                    }

                    if (latin_key == Gdk.Key.i) {
                        sync_other_panel_to_current();
                        return Gdk.EVENT_STOP;
                    }

                    // Double Escape: clear all tags / marks in the active panel
                    if (keyval == Gdk.Key.Escape) {
                        if (active_panel != null && !cmd_entry.has_focus) {
                            active_panel.clear_tags();
                            active_panel.grab_focus_to_list();
                            return Gdk.EVENT_STOP;
                        }
                        return Gdk.EVENT_PROPAGATE;
                    }
                }

                // Alt+I: Direct shortcut to sync opposite panel to active directory
                if (latin_key == Gdk.Key.i &&
                    (state & Gdk.ModifierType.ALT_MASK) != 0 &&
                    (state & Gdk.ModifierType.CONTROL_MASK) == 0) {
                    sync_other_panel_to_current();
                    return Gdk.EVENT_STOP;
                }

                // Escape closes quick filter if active in active panel, or arms Escape sequence
                if (keyval == Gdk.Key.Escape && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    if (active_panel != null && active_panel.is_filter_active) {
                        active_panel.hide_filter();
                        return Gdk.EVENT_STOP;
                    }

                    escape_sequence_pending = true;
                    if (escape_sequence_timeout_id != 0) {
                        Source.remove(escape_sequence_timeout_id);
                    }
                    escape_sequence_timeout_id = Timeout.add(1200, () => {
                        escape_sequence_pending = false;
                        escape_sequence_timeout_id = 0;
                        return Source.REMOVE;
                    });
                    return Gdk.EVENT_PROPAGATE;
                }

                // Insert / KP_Insert: toggle tag on item in active panel and advance cursor
                if ((keyval == Gdk.Key.Insert || keyval == Gdk.Key.KP_Insert) &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    if (active_panel != null && !cmd_entry.has_focus) {
                        active_panel.toggle_tag_current_item();
                        return Gdk.EVENT_STOP;
                    }
                }

                // Plus on keypad (KP_Add) or Shift++ in number row (plus): Select by mask
                if ((keyval == Gdk.Key.KP_Add || keyval == Gdk.Key.plus) &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    if (active_panel != null && !active_panel.is_filter_active && !cmd_entry.has_focus) {
                        prompt_select_by_mask();
                        return Gdk.EVENT_STOP;
                    }
                }

                // Ctrl+Shift+H: toggle window header bar visibility
                if (latin_key == Gdk.Key.h &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    header_bar.visible = !header_bar.visible;
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+S: quick directory filter (Midnight Commander style)
                if (latin_key == Gdk.Key.s && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (active_panel != null) {
                        active_panel.show_filter();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Tab switches active panel (unless user is typing in command line)
                if (keyval == Gdk.Key.Tab && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    toggle_active_panel();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Enter or Ctrl+KP_Enter: Insert selected file or directory name into command line
                if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.ISO_Enter) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    insert_selected_name_to_command_bar();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Shift+T: rename current tab in active panel (max 15 chars)
                if (latin_key == Gdk.Key.t && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 && 
                    (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    if (active_panel != null) {
                        active_panel.prompt_rename_current_tab(this);
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+T: open new tab in active panel
                if (latin_key == Gdk.Key.t && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & Gdk.ModifierType.SHIFT_MASK) == 0) {
                    if (active_panel != null) {
                        active_panel.open_new_tab();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+W: close current tab in active panel
                if (latin_key == Gdk.Key.w && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (active_panel != null) {
                        active_panel.close_current_tab();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Alt+T: toggle Brief / Full view mode for active panel
                if (latin_key == Gdk.Key.t && (state & Gdk.ModifierType.ALT_MASK) != 0) {
                    if (active_panel != null) {
                        active_panel.toggle_view_mode();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl++ or Ctrl+= : increase brief view column width
                if ((keyval == Gdk.Key.plus || keyval == Gdk.Key.equal || keyval == Gdk.Key.KP_Add) && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    var config = ConfigManager.get_instance();
                    if (config.brief_column_width < 800) {
                        config.brief_column_width = int.min(800, config.brief_column_width + 10);
                        config.save();
                        apply_preferences();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+- : decrease brief view column width
                if ((keyval == Gdk.Key.minus || keyval == Gdk.Key.KP_Subtract) && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    var config = ConfigManager.get_instance();
                    if (config.brief_column_width > 100) {
                        config.brief_column_width = int.max(100, config.brief_column_width - 10);
                        config.save();
                        apply_preferences();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Alt+Up: Go to parent directory (same as Backspace or clicking "..")
                if (keyval == Gdk.Key.Up && (state & Gdk.ModifierType.ALT_MASK) != 0) {
                    if (active_panel != null) {
                        active_panel.go_up();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Space: calculate folder or file size in active panel
                if (keyval == Gdk.Key.space && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (active_panel != null) {
                        active_panel.calculate_selected_size();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Left Arrow: Jump to top/first item (Full view or leftmost column in Brief view)
                // (Unless user is typing in the command line)
                if (keyval == Gdk.Key.Left && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    if (active_panel != null && active_panel.handle_left_arrow()) {
                        return Gdk.EVENT_STOP;
                    }
                }

                // Right Arrow: Jump to end/last item (Full view or rightmost column in Brief view)
                // (Unless user is typing in the command line)
                if (keyval == Gdk.Key.Right && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    if (active_panel != null && active_panel.handle_right_arrow()) {
                        return Gdk.EVENT_STOP;
                    }
                }

                // F1: show Shortcuts Dialog
                if (keyval == Gdk.Key.F1) {
                    ShortcutsDialog.show(this);
                    return Gdk.EVENT_STOP;
                }

                // F5: Copy
                if (keyval == Gdk.Key.F5) {
                    on_f5_copy();
                    return Gdk.EVENT_STOP;
                }

                // F6: Move (or Shift+F6: Rename)
                if (keyval == Gdk.Key.F6) {
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        on_shift_f6_rename();
                    } else {
                        on_f6_move();
                    }
                    return Gdk.EVENT_STOP;
                }

                // F7: Mkdir
                if (keyval == Gdk.Key.F7) {
                    on_f7_mkdir();
                    return Gdk.EVENT_STOP;
                }

                // Delete or Shift+Delete / KP_Delete
                if ((keyval == Gdk.Key.Delete || keyval == Gdk.Key.KP_Delete) &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    bool permanent = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                    on_delete(permanent);
                    return Gdk.EVENT_STOP;
                }

                // F8 / Shift+F8: Delete
                if (keyval == Gdk.Key.F8) {
                    bool permanent = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                    on_delete(permanent);
                    return Gdk.EVENT_STOP;
                }

                // F10: Quit
                if (keyval == Gdk.Key.F10) {
                    close();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+,: show Preferences Dialog
                if (latin_key == Gdk.Key.comma && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    prompt_preferences_dialog();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Q: quit application
                if (latin_key == Gdk.Key.q && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    close();
                    return Gdk.EVENT_STOP;
                }

                return Gdk.EVENT_PROPAGATE;
            });
            target_widget.add_controller(key_controller);
        }

        private void on_panel_activated(FilePanel panel) {
            activate_panel(panel, false);
        }

        private void on_panel_directory_changed(File new_dir) {
            // Panel directory changed
        }

        private void on_command_char_typed(string ch) {
            cmd_entry.text = cmd_entry.text + ch;
            cmd_entry.grab_focus();
            cmd_entry.set_position(-1);
        }

        private void insert_selected_name_to_command_bar() {
            if (active_panel == null) return;
            var item = active_panel.get_selected_item();
            if (item == null || item.is_parent_dir) return;

            string name = item.display_name;
            // Check if name contains spaces or shell special characters
            string formatted_name;
            if (name.contains(" ") || name.contains("\t") || name.contains("\"") || name.contains("'") ||
                name.contains("$") || name.contains("`") || name.contains("&") || name.contains(";") ||
                name.contains("(") || name.contains(")")) {
                // Escape existing double quotes and wrap in double quotes
                string escaped = name.replace("\"", "\\\"");
                formatted_name = @"\"$escaped\"";
            } else {
                formatted_name = name;
            }

            string current_text = cmd_entry.text;
            if (current_text.length > 0 && !current_text.has_suffix(" ")) {
                cmd_entry.text = current_text + " " + formatted_name + " ";
            } else {
                cmd_entry.text = current_text + formatted_name + " ";
            }

            cmd_entry.grab_focus();
            cmd_entry.set_position(-1);
        }

        public void toggle_active_panel() {
            if (active_panel == left_panel) {
                activate_panel(right_panel, true);
            } else {
                activate_panel(left_panel, true);
            }
        }

        public void activate_panel(FilePanel panel, bool focus_list = true) {
            active_panel = panel;
            left_panel.set_active(panel == left_panel);
            right_panel.set_active(panel == right_panel);
            if (focus_list) {
                active_panel.grab_focus_to_list();
            }
        }

        private void on_command_entered() {
            var cmd = cmd_entry.text.strip();
            if (cmd.length > 0) {
                if (command_history.length == 0 || command_history[command_history.length - 1] != cmd) {
                    command_history.add(cmd);
                }
                history_index = -1;
                saved_input = "";
                cmd_entry.text = "";

                if (active_panel != null && active_panel.current_directory != null) {
                    if (!handle_builtin_cd(cmd)) {
                        execute_shell_command.begin(cmd, active_panel.current_directory);
                    }
                }
            }
            if (active_panel != null) {
                active_panel.grab_focus_to_list();
            }
        }

        private bool handle_builtin_cd(string cmd) {
            string trimmed = cmd.strip();
            if (trimmed == "cd" || trimmed.has_prefix("cd ") || trimmed.has_prefix("cd\t")) {
                string target_raw = "";
                if (trimmed.length > 2) {
                    target_raw = trimmed.substring(2).strip();
                }

                // Strip quotes if present
                if ((target_raw.has_prefix("\"") && target_raw.has_suffix("\"")) ||
                    (target_raw.has_prefix("'") && target_raw.has_suffix("'"))) {
                    if (target_raw.length >= 2) {
                        target_raw = target_raw.substring(1, target_raw.length - 2);
                    }
                } else {
                    target_raw = target_raw.replace("\\ ", " ");
                }

                File target_file;
                if (target_raw.length == 0 || target_raw == "~") {
                    target_file = File.new_for_path(Environment.get_home_dir());
                } else if (target_raw.has_prefix("~/")) {
                    string rel = target_raw.substring(2);
                    target_file = File.new_for_path(Path.build_filename(Environment.get_home_dir(), rel));
                } else if (target_raw == "..") {
                    var parent = active_panel.current_directory.get_parent();
                    target_file = (parent != null) ? parent : active_panel.current_directory;
                } else if (target_raw.has_prefix("/") || target_raw.contains("://")) {
                    target_file = File.new_for_commandline_arg(target_raw);
                } else {
                    target_file = active_panel.current_directory.resolve_relative_path(target_raw);
                }

                if (target_file.query_exists()) {
                    var file_type = target_file.query_file_type(FileQueryInfoFlags.NONE);
                    if (file_type == FileType.DIRECTORY) {
                        active_panel.load_directory(target_file);
                    } else {
                        show_error_dialog("cd: Not a directory", target_raw);
                    }
                } else {
                    show_error_dialog("cd: No such directory", target_raw);
                }
                return true;
            }
            return false;
        }

        private bool on_command_entry_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Escape) {
                cmd_entry.text = "";
                history_index = -1;
                saved_input = "";
                if (active_panel != null) {
                    active_panel.grab_focus_to_list();
                }
                return Gdk.EVENT_STOP;
            }

            // Command history navigation
            if (keyval == Gdk.Key.Up) {
                if (command_history.length == 0) return Gdk.EVENT_STOP;

                if (history_index == -1) {
                    saved_input = cmd_entry.text;
                    history_index = (int) command_history.length - 1;
                } else if (history_index > 0) {
                    history_index--;
                }

                cmd_entry.text = command_history[history_index];
                cmd_entry.set_position(-1);
                return Gdk.EVENT_STOP;
            }

            if (keyval == Gdk.Key.Down) {
                if (history_index != -1) {
                    if (history_index < (int) command_history.length - 1) {
                        history_index++;
                        cmd_entry.text = command_history[history_index];
                    } else {
                        history_index = -1;
                        cmd_entry.text = saved_input;
                    }
                    cmd_entry.set_position(-1);
                }
                return Gdk.EVENT_STOP;
            }

            return Gdk.EVENT_PROPAGATE;
        }

        private async void execute_shell_command(string command_str, File working_dir) {
            string? cwd_path = working_dir.get_path();
            if (cwd_path == null) {
                cwd_path = Environment.get_home_dir();
            }

            string shell_setting = ConfigManager.get_instance().command_shell.strip();
            if (shell_setting.length == 0) {
                shell_setting = "/bin/bash";
            }

            string? shell_bin = null;
            if (shell_setting.contains("/")) {
                var f = File.new_for_path(shell_setting);
                if (f.query_exists()) {
                    shell_bin = shell_setting;
                }
            } else {
                shell_bin = Environment.find_program_in_path(shell_setting);
            }

            if (shell_bin == null) {
                show_error_dialog("Shell Interpreter Error",
                    @"Configured shell interpreter '$shell_setting' was not found or is not executable.\nPlease check your shell path in Preferences (Ctrl+,).");
                return;
            }

            try {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                launcher.set_cwd(cwd_path);

                string[] argv;
                string base_name = Path.get_basename(shell_bin);
                if (base_name == "bash" || base_name == "zsh") {
                    argv = new string[] { shell_bin, "-l", "-i", "-c", command_str };
                } else {
                    argv = new string[] { shell_bin, "-c", command_str };
                }
                var subprocess = launcher.spawnv(argv);

                string stdout_buf;
                string stderr_buf;
                yield subprocess.communicate_utf8_async(null, null, out stdout_buf, out stderr_buf);

                if (!subprocess.get_successful()) {
                    int status = subprocess.get_exit_status();
                    string err_msg = stderr_buf.strip();
                    if (err_msg.length == 0) {
                        err_msg = stdout_buf.strip();
                    }
                    if (err_msg.length == 0) {
                        err_msg = @"Command exited with code $status";
                    }
                    show_error_dialog(@"Command failed: $command_str", err_msg);
                }

                // Refresh both panels as files might have been created or modified
                left_panel.refresh();
                right_panel.refresh();
            } catch (Error e) {
                show_error_dialog("Execution Error", @"Cannot execute '$command_str': $(e.message)");
            }
        }

        public void show_error_dialog(string title, string message) {
            var dialog = new Adw.AlertDialog(title, message);
            dialog.add_response("ok", "OK");
            dialog.set_default_response("ok");
            dialog.set_close_response("ok");
            dialog.set_response_appearance("ok", Adw.ResponseAppearance.DEFAULT);
            dialog.response.connect(() => {
                if (active_panel != null) {
                    active_panel.grab_focus_to_list();
                }
            });
            dialog.present(this);
        }

        private FilePanel get_opposite_panel() {
            return (active_panel == left_panel) ? right_panel : left_panel;
        }

        private void sync_other_panel_to_current() {
            if (active_panel == null || active_panel.current_directory == null) return;
            var opp = get_opposite_panel();
            string? target_name = null;
            var item = active_panel.get_selected_item();
            if (item != null && !item.is_parent_dir) {
                target_name = item.name;
            }
            opp.load_directory(active_panel.current_directory, target_name);
        }

        private void prompt_select_by_mask() {
            if (active_panel == null) return;

            var dialog = new Adw.AlertDialog("Select by Mask", "Enter filename mask (e.g. *.lst, *abc*):");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("select", "Select");
            dialog.set_default_response("select");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("select", Adw.ResponseAppearance.SUGGESTED);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_start = 12;
            box.margin_end = 12;
            box.margin_top = 8;
            box.margin_bottom = 8;

            var entry = new Gtk.Entry();
            entry.text = "*";
            entry.placeholder_text = "*.lst, *abc*";

            var check_dirs = new Gtk.CheckButton.with_label("Apply to folders");
            check_dirs.active = false;

            box.append(entry);
            box.append(check_dirs);
            dialog.set_extra_child(box);

            entry.activate.connect(() => {
                string pattern = entry.text.strip();
                bool inc_dirs = check_dirs.active;
                dialog.force_close();
                if (pattern.length > 0 && active_panel != null) {
                    active_panel.select_by_mask(pattern, inc_dirs);
                    active_panel.grab_focus_to_list();
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "select") {
                    string pattern = entry.text.strip();
                    if (pattern.length > 0 && active_panel != null) {
                        active_panel.select_by_mask(pattern, check_dirs.active);
                    }
                }
                if (active_panel != null) active_panel.grab_focus_to_list();
            });

            GLib.Idle.add(() => {
                entry.grab_focus();
                entry.select_region(0, -1);
                return GLib.Source.REMOVE;
            });
        }

        private void on_f7_mkdir() {
            if (active_panel == null || active_panel.current_directory == null) return;
            var current_dir = active_panel.current_directory;

            var dialog = new Adw.AlertDialog("Create New Folder", "Enter the name for the new folder:");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("create", "Create");
            dialog.set_default_response("create");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED);

            var entry = new Gtk.Entry();
            entry.placeholder_text = "Folder name...";
            entry.margin_start = 12;
            entry.margin_end = 12;
            entry.margin_top = 8;
            entry.margin_bottom = 8;
            dialog.set_extra_child(entry);

            var target_panel = active_panel;
            bool action_executed = false;

            entry.activate.connect(() => {
                if (action_executed) return;
                action_executed = true;
                string name = entry.text.strip();
                dialog.force_close();
                if (name.length > 0) {
                    do_make_directory.begin(target_panel, current_dir, name);
                } else {
                    target_panel.grab_focus_to_list();
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (action_executed) return;
                if (resp == "create") {
                    action_executed = true;
                    string name = entry.text.strip();
                    if (name.length > 0) {
                        do_make_directory.begin(target_panel, current_dir, name);
                    } else {
                        target_panel.grab_focus_to_list();
                    }
                } else {
                    target_panel.grab_focus_to_list();
                }
            });

            GLib.Idle.add(() => {
                entry.grab_focus();
                return GLib.Source.REMOVE;
            });
        }

        private async void do_make_directory(FilePanel panel, File parent_dir, string name) {
            if (name.contains("/")) {
                show_error_dialog("Invalid Folder Name", "Folder name cannot contain '/' path separators.");
                panel.grab_focus_to_list();
                return;
            }
            var target = parent_dir.get_child(name);
            try {
                yield FileOperationService.make_directory(target);
                panel.load_directory(parent_dir, name);
                activate_panel(panel, true);
                var opp = (panel == left_panel) ? right_panel : left_panel;
                if (opp.current_directory != null && opp.current_directory.equal(parent_dir)) {
                    opp.refresh();
                }
                panel.grab_focus_to_list();
            } catch (Error e) {
                show_error_dialog("Create Folder Error", FileOperationService.format_error(e, "create folder"));
                panel.grab_focus_to_list();
            }
        }

        private void on_delete(bool permanent_default = false) {
            if (active_panel == null) return;

            var tagged_items = active_panel.get_tagged_items();
            if (tagged_items.length > 0) {
                var dialog = new Adw.AlertDialog(
                    "Delete Items",
                    @"Delete $(tagged_items.length) selected items?"
                );
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("delete", "Delete");
                dialog.set_default_response("cancel");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);

                var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                box.halign = Gtk.Align.CENTER;
                box.margin_top = 8;
                box.margin_bottom = 4;
                var perm_check = new Gtk.CheckButton.with_label("Delete permanently (bypass Trash)");
                perm_check.active = permanent_default;
                box.append(perm_check);
                dialog.set_extra_child(box);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "delete") {
                        do_delete_multiple_items.begin(tagged_items, perm_check.active);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            var item = active_panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Delete", "Cannot delete parent directory '..'.");
                return;
            }

            string item_name = item.display_name;
            string desc = item.is_dir ?
                @"Delete folder '$item_name' and all its contents?" :
                @"Delete file '$item_name'?";

            var dialog = new Adw.AlertDialog("Delete Item", desc);
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("delete", "Delete");
            dialog.set_default_response("cancel");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            box.halign = Gtk.Align.CENTER;
            box.margin_top = 8;
            box.margin_bottom = 4;
            var perm_check = new Gtk.CheckButton.with_label("Delete permanently (bypass Trash)");
            perm_check.active = permanent_default;
            box.append(perm_check);
            dialog.set_extra_child(box);

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "delete") {
                    do_delete_item.begin(item.file, perm_check.active);
                } else {
                    if (active_panel != null) active_panel.grab_focus_to_list();
                }
            });
        }

        private async void do_delete_item(File target, bool permanent) {
            try {
                if (permanent) {
                    yield FileOperationService.delete_recursive(target);
                } else {
                    yield FileOperationService.trash_file(target);
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                show_error_dialog("Delete Error", FileOperationService.format_error(e, permanent ? "delete" : "trash"));
            }
        }

        private async void do_delete_multiple_items(GenericArray<FileItem> items, bool permanent) {
            var cancellable = new Cancellable();
            string op_title = permanent ? @"Permanently deleting $(items.length) items" : @"Moving $(items.length) items to Trash";
            var dlg = new OperationProgressDialog(op_title, cancellable);
            dlg.present();

            try {
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    dlg.update_progress(it.display_name, i, items.length);
                    if (permanent) {
                        yield FileOperationService.delete_recursive(it.file, cancellable);
                    } else {
                        yield FileOperationService.trash_file(it.file, cancellable);
                    }
                }
                dlg.finish();
                if (!cancellable.is_cancelled() && active_panel != null) {
                    active_panel.clear_tags();
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                dlg.finish();
                if (!e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_error_dialog("Delete Error", FileOperationService.format_error(e, permanent ? "delete" : "trash"));
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private void on_f5_copy() {
            if (active_panel == null) return;

            var tagged_items = active_panel.get_tagged_items();
            var opp = get_opposite_panel();
            File? dest_dir = opp.current_directory;

            if (tagged_items.length > 0) {
                if (dest_dir == null) {
                    show_error_dialog("Copy Error", "Opposite panel has no directory open.");
                    return;
                }
                if (active_panel.current_directory != null && dest_dir.equal(active_panel.current_directory)) {
                    show_error_dialog("Copy Error", "Cannot copy selected files: destination is the same directory.");
                    return;
                }

                string dest_path = dest_dir.get_path();
                if (dest_path == null) dest_path = dest_dir.get_parse_name();

                var dialog = new Adw.AlertDialog("Copy Selected Items", @"Copy $(tagged_items.length) items to:\n$dest_path");
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("copy", "Copy");
                dialog.set_default_response("copy");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("copy", Adw.ResponseAppearance.SUGGESTED);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "copy") {
                        do_copy_multiple_items.begin(tagged_items, dest_dir);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            var item = active_panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Copy", "Please select a file or folder to copy.");
                return;
            }

            File default_dest_dir = (dest_dir != null) ? dest_dir : active_panel.current_directory;
            File default_target_file = default_dest_dir.get_child(item.name);

            string default_dest_path = default_target_file.get_path();
            if (default_dest_path == null) {
                default_dest_path = default_target_file.get_parse_name();
            }

            var dialog = new Adw.AlertDialog("Copy", @"Copy '$(item.display_name)' to:");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("copy", "Copy");
            dialog.set_default_response("copy");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("copy", Adw.ResponseAppearance.SUGGESTED);

            var entry = new Gtk.Entry();
            entry.text = default_dest_path;
            entry.margin_start = 12;
            entry.margin_end = 12;
            entry.margin_top = 8;
            entry.margin_bottom = 8;
            dialog.set_extra_child(entry);

            entry.activate.connect(() => {
                string dest_input = entry.text.strip();
                dialog.force_close();
                if (dest_input.length > 0) {
                    prompt_execute_copy.begin(item, dest_input);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "copy") {
                    string dest_input = entry.text.strip();
                    if (dest_input.length > 0) {
                        prompt_execute_copy.begin(item, dest_input);
                    }
                } else {
                    if (active_panel != null) active_panel.grab_focus_to_list();
                }
            });

            GLib.Idle.add(() => {
                entry.grab_focus();
                entry.set_position(-1);
                return GLib.Source.REMOVE;
            });
        }

        private async void prompt_execute_copy(FileItem item, string dest_input) {
            File? dest_target = resolve_dest_file(item, dest_input, "Copy");
            if (dest_target == null) return;

            if (dest_target.equal(item.file)) {
                show_error_dialog("Copy Error", "Source and destination cannot be the same.");
                return;
            }

            if (dest_target.query_exists()) {
                var conflict_dlg = new Adw.AlertDialog(
                    "File Already Exists",
                    @"Destination '$(dest_target.get_basename())' already exists. Do you want to overwrite it?"
                );
                conflict_dlg.add_response("cancel", "Cancel");
                conflict_dlg.add_response("overwrite", "Overwrite");
                conflict_dlg.set_default_response("cancel");
                conflict_dlg.set_close_response("cancel");
                conflict_dlg.set_response_appearance("overwrite", Adw.ResponseAppearance.DESTRUCTIVE);

                conflict_dlg.choose.begin(this, null, (obj, res) => {
                    string resp = conflict_dlg.choose.end(res);
                    if (resp == "overwrite") {
                        do_copy_file.begin(item.file, dest_target, true);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
            } else {
                yield do_copy_file(item.file, dest_target, false);
            }
        }

        private async void do_copy_file(File source, File dest, bool overwrite) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Copying $(source.get_basename())", cancellable);
            dlg.present();

            var tracker = new CopyProgressTracker();
            try {
                // Calculate total size first for progress bar
                int64 total_size = yield FileOperationService.calculate_total_size(source, cancellable);
                tracker.total_bytes = total_size;
                dlg.update_progress(source.get_basename(), 0, total_size);

                yield FileOperationService.copy_file_or_dir(
                    source,
                    dest,
                    overwrite,
                    cancellable,
                    (cur_filename, current_b, total_b) => {
                        dlg.update_progress(cur_filename, current_b, total_b);
                    },
                    tracker
                );

                dlg.finish();
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                dlg.finish();
                if (!e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_error_dialog("Copy Error", FileOperationService.format_error(e, "copy"));
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private async void do_copy_multiple_items(GenericArray<FileItem> items, File dest_dir) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Copying $(items.length) items", cancellable);
            dlg.present();

            var tracker = new CopyProgressTracker();
            try {
                dlg.update_progress(@"Calculating size of $(items.length) items...", 0, 0);
                int64 total_size = 0;
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    total_size += yield FileOperationService.calculate_total_size(items[i].file, cancellable);
                }
                tracker.total_bytes = total_size;
                dlg.update_progress(@"Starting copy...", 0, total_size);

                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    var dest_child = dest_dir.get_child(it.name);

                    yield FileOperationService.copy_file_or_dir(
                        it.file,
                        dest_child,
                        true,
                        cancellable,
                        (cur_filename, current_b, total_b) => {
                            dlg.update_progress(cur_filename, current_b, total_b);
                        },
                        tracker
                    );
                }

                dlg.finish();
                if (!cancellable.is_cancelled() && active_panel != null) {
                    active_panel.clear_tags();
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                dlg.finish();
                if (!e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_error_dialog("Copy Error", FileOperationService.format_error(e, "copy"));
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private void on_f6_move() {
            if (active_panel == null) return;

            var tagged_items = active_panel.get_tagged_items();
            var opp = get_opposite_panel();
            File? dest_dir = opp.current_directory;

            if (tagged_items.length > 0) {
                if (dest_dir == null) {
                    show_error_dialog("Move Error", "Opposite panel has no directory open.");
                    return;
                }
                if (active_panel.current_directory != null && dest_dir.equal(active_panel.current_directory)) {
                    show_error_dialog("Move Error", "Cannot move selected files: destination is the same directory.");
                    return;
                }

                string dest_path = dest_dir.get_path();
                if (dest_path == null) dest_path = dest_dir.get_parse_name();

                var dialog = new Adw.AlertDialog("Move Selected Items", @"Move $(tagged_items.length) items to:\n$dest_path");
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("move", "Move");
                dialog.set_default_response("move");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("move", Adw.ResponseAppearance.SUGGESTED);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "move") {
                        do_move_multiple_items.begin(tagged_items, dest_dir);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            var item = active_panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Move", "Please select a file or folder to move.");
                return;
            }

            File default_dest_dir = (dest_dir != null) ? dest_dir : active_panel.current_directory;
            File default_target_file = default_dest_dir.get_child(item.name);

            string default_dest_path = default_target_file.get_path();
            if (default_dest_path == null) {
                default_dest_path = default_target_file.get_parse_name();
            }

            var dialog = new Adw.AlertDialog("Move", @"Move '$(item.display_name)' to:");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("move", "Move");
            dialog.set_default_response("move");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("move", Adw.ResponseAppearance.SUGGESTED);

            var entry = new Gtk.Entry();
            entry.text = default_dest_path;
            entry.margin_start = 12;
            entry.margin_end = 12;
            entry.margin_top = 8;
            entry.margin_bottom = 8;
            dialog.set_extra_child(entry);

            entry.activate.connect(() => {
                string dest_input = entry.text.strip();
                dialog.force_close();
                if (dest_input.length > 0) {
                    prompt_execute_move.begin(item, dest_input);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "move") {
                    string dest_input = entry.text.strip();
                    if (dest_input.length > 0) {
                        prompt_execute_move.begin(item, dest_input);
                    }
                } else {
                    if (active_panel != null) active_panel.grab_focus_to_list();
                }
            });

            GLib.Idle.add(() => {
                entry.grab_focus();
                entry.set_position(-1);
                return GLib.Source.REMOVE;
            });
        }

        private void on_shift_f6_rename() {
            if (active_panel == null) return;
            var item = active_panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Rename", "Please select a file or folder to rename.");
                return;
            }

            var dialog = new Adw.AlertDialog("Rename", @"Rename '$(item.display_name)' to:");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("rename", "Rename");
            dialog.set_default_response("rename");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("rename", Adw.ResponseAppearance.SUGGESTED);

            var entry = new Gtk.Entry();
            entry.text = item.display_name;
            entry.margin_start = 12;
            entry.margin_end = 12;
            entry.margin_top = 8;
            entry.margin_bottom = 8;
            dialog.set_extra_child(entry);

            entry.activate.connect(() => {
                string new_name = entry.text.strip();
                dialog.force_close();
                if (new_name.length > 0 && new_name != item.display_name) {
                    prompt_execute_rename.begin(item, new_name);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "rename") {
                    string new_name = entry.text.strip();
                    if (new_name.length > 0 && new_name != item.display_name) {
                        prompt_execute_rename.begin(item, new_name);
                    }
                } else {
                    if (active_panel != null) active_panel.grab_focus_to_list();
                }
            });

            GLib.Idle.add(() => {
                entry.grab_focus();
                // Select name excluding extension if file
                int dot_pos = item.display_name.last_index_of_char('.');
                if (!item.is_dir && dot_pos > 0) {
                    entry.select_region(0, dot_pos);
                } else {
                    entry.select_region(0, -1);
                }
                return GLib.Source.REMOVE;
            });
        }

        private async void prompt_execute_rename(FileItem item, string new_name) {
            if (new_name.contains("/")) {
                show_error_dialog("Rename Error", "File or folder name cannot contain '/' path separators.");
                return;
            }

            var parent_dir = item.file.get_parent();
            if (parent_dir == null) return;
            var dest_target = parent_dir.get_child(new_name);

            if (dest_target.query_exists()) {
                var conflict_dlg = new Adw.AlertDialog(
                    "File Already Exists",
                    @"A file or folder named '$new_name' already exists. Do you want to overwrite it?"
                );
                conflict_dlg.add_response("cancel", "Cancel");
                conflict_dlg.add_response("overwrite", "Overwrite");
                conflict_dlg.set_default_response("cancel");
                conflict_dlg.set_close_response("cancel");
                conflict_dlg.set_response_appearance("overwrite", Adw.ResponseAppearance.DESTRUCTIVE);

                conflict_dlg.choose.begin(this, null, (obj, res) => {
                    string resp = conflict_dlg.choose.end(res);
                    if (resp == "overwrite") {
                        do_move_file.begin(item.file, dest_target, true);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
            } else {
                yield do_move_file(item.file, dest_target, false);
            }
        }

        private async void prompt_execute_move(FileItem item, string dest_input) {
            File? dest_target = resolve_dest_file(item, dest_input, "Move");
            if (dest_target == null) return;

            if (dest_target.equal(item.file)) {
                show_error_dialog("Move Error", "Source and destination cannot be the same.");
                return;
            }

            if (dest_target.query_exists()) {
                var conflict_dlg = new Adw.AlertDialog(
                    "File Already Exists",
                    @"Destination '$(dest_target.get_basename())' already exists. Do you want to overwrite it?"
                );
                conflict_dlg.add_response("cancel", "Cancel");
                conflict_dlg.add_response("overwrite", "Overwrite");
                conflict_dlg.set_default_response("cancel");
                conflict_dlg.set_close_response("cancel");
                conflict_dlg.set_response_appearance("overwrite", Adw.ResponseAppearance.DESTRUCTIVE);

                conflict_dlg.choose.begin(this, null, (obj, res) => {
                    string resp = conflict_dlg.choose.end(res);
                    if (resp == "overwrite") {
                        do_move_file.begin(item.file, dest_target, true);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
            } else {
                yield do_move_file(item.file, dest_target, false);
            }
        }

        private async void do_move_file(File source, File dest, bool overwrite) {
            try {
                yield FileOperationService.move_file_or_dir(source, dest, overwrite);
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                show_error_dialog("Move Error", FileOperationService.format_error(e, "move"));
            }
        }

        private async void do_move_multiple_items(GenericArray<FileItem> items, File dest_dir) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Moving $(items.length) items", cancellable);
            dlg.present();

            try {
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    var dest_child = dest_dir.get_child(it.name);

                    dlg.update_progress(it.display_name, i, items.length);
                    yield FileOperationService.move_file_or_dir(it.file, dest_child, true, cancellable);
                }

                dlg.finish();
                if (!cancellable.is_cancelled() && active_panel != null) {
                    active_panel.clear_tags();
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                dlg.finish();
                if (!e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_error_dialog("Move Error", FileOperationService.format_error(e, "move"));
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private File? resolve_dest_file(FileItem item, string dest_input, string op_name) {
            string raw = dest_input.strip();
            File dest_file;
            if (raw.has_prefix("~/")) {
                dest_file = File.new_for_path(Path.build_filename(Environment.get_home_dir(), raw.substring(2)));
            } else if (raw == "~") {
                dest_file = File.new_for_path(Environment.get_home_dir());
            } else if (raw.has_prefix("/") || raw.contains("://")) {
                dest_file = File.new_for_commandline_arg(raw);
            } else {
                dest_file = active_panel.current_directory.resolve_relative_path(raw);
            }

            // Check if the input specifies an existing directory directly
            if (dest_file.query_exists()) {
                try {
                    var info = dest_file.query_info(FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NONE);
                    if (info.get_file_type() == FileType.DIRECTORY) {
                        return dest_file.get_child(item.name);
                    }
                } catch (Error e) {}
                return dest_file;
            }

            // If destination does not exist, verify that its parent directory exists!
            var parent = dest_file.get_parent();
            if (parent != null && !parent.query_exists()) {
                string parent_path = parent.get_path();
                if (parent_path == null) parent_path = parent.get_parse_name();
                show_error_dialog(@"$op_name Error", @"The destination directory does not exist: $parent_path");
                return null;
            }

            return dest_file;
        }

        public void save_state() {
            var config = ConfigManager.get_instance();
            int cur_w, cur_h;
            get_default_size(out cur_w, out cur_h);
            if (cur_w <= 0) cur_w = get_width();
            if (cur_h <= 0) cur_h = get_height();

            config.window_width = cur_w > 0 ? cur_w : 1024;
            config.window_height = cur_h > 0 ? cur_h : 680;
            config.is_maximized = maximized;
            config.paned_position = paned.position;
            config.active_pane = (active_panel == right_panel) ? "right" : "left";

            // Left panel state
            config.left_tabs = left_panel.get_tab_paths();
            config.left_tab_titles = left_panel.get_tab_titles();
            config.left_active_tab = left_panel.get_active_tab_index();
            config.left_brief_view = left_panel.is_brief_view;
            config.left_show_hidden = left_panel.show_hidden;

            // Right panel state
            config.right_tabs = right_panel.get_tab_paths();
            config.right_tab_titles = right_panel.get_tab_titles();
            config.right_active_tab = right_panel.get_active_tab_index();
            config.right_brief_view = right_panel.is_brief_view;
            config.right_show_hidden = right_panel.show_hidden;

            config.save();
        }

        private bool on_close_requested() {
            save_state();
            return false;
        }

        public void prompt_preferences_dialog() {
            PreferencesDialog.show(this, this);
        }

        public void apply_preferences() {
            var config = ConfigManager.get_instance();
            left_panel.set_path_toolbar_visible(config.show_path_toolbar);
            right_panel.set_path_toolbar_visible(config.show_path_toolbar);
            if (fn_bar != null) {
                fn_bar.visible = config.show_function_bar;
            }
            left_panel.update_brief_column_width();
            right_panel.update_brief_column_width();
            apply_font_styles();
        }

        public override void unmap() {
            save_state();
            base.unmap();
        }
    }
}
