namespace VCommander {

    public class MainWindow : Adw.ApplicationWindow {
        private Gtk.Paned paned;
        public FilePanel left_panel { get; private set; }
        public FilePanel right_panel { get; private set; }
        public FilePanel active_panel { get; private set; }

        private Gtk.Label prompt_label;
        private Gtk.Entry cmd_entry;
        private GenericArray<string> command_history;
        private int history_index = -1;
        private string saved_input = "";

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

        private void load_css_styles() {
            var provider = new Gtk.CssProvider();
            var css_file = File.new_for_path("data/style.css");
            if (css_file.query_exists()) {
                provider.load_from_file(css_file);
                Gtk.StyleContext.add_provider_for_display(
                    Gdk.Display.get_default(),
                    provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
            }
        }

        private void build_ui() {
            var config = ConfigManager.get_instance();
            var root_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            // Header Bar
            var header_bar = new Adw.HeaderBar();
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

            paned.start_child = left_panel;
            paned.end_child = right_panel;
            paned.position = config.paned_position > 0 ? config.paned_position : 512;

            root_box.append(paned);

            // Bottom MC-style Command Line Bar
            build_command_bar(root_box);

            content = root_box;

            setup_keyboard_shortcuts(root_box);
        }

        private void build_command_bar(Gtk.Box parent_box) {
            var command_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            command_bar.add_css_class("command-bar");

            prompt_label = new Gtk.Label("$ ");
            prompt_label.add_css_class("command-prompt");
            command_bar.append(prompt_label);

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

        private void setup_keyboard_shortcuts(Gtk.Widget target_widget) {
            var key_controller = new Gtk.EventControllerKey();
            key_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                uint latin_key = KeyUtils.to_latin(keyval, keycode);

                // Tab switches active panel (unless user is typing in command line)
                if (keyval == Gdk.Key.Tab && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    toggle_active_panel();
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
            update_prompt();
        }

        private void on_command_char_typed(string ch) {
            cmd_entry.text = cmd_entry.text + ch;
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
            update_prompt();
            if (focus_list) {
                active_panel.grab_focus_to_list();
            }
        }

        private void update_prompt() {
            if (active_panel == null || active_panel.current_directory == null) {
                prompt_label.label = "$ ";
                return;
            }
            string folder = active_panel.current_directory.get_basename();
            if (folder == null || folder.length == 0) {
                folder = "/";
            }
            prompt_label.label = "[" + folder + "] $ ";
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

            try {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                launcher.set_cwd(cwd_path);

                string[] argv = { "bash", "-c", command_str };
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
            dialog.set_response_appearance("ok", Adw.ResponseAppearance.DEFAULT);
            dialog.present(this);
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
        }

        public override void unmap() {
            save_state();
            base.unmap();
        }
    }
}
