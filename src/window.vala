namespace VCommander {

    public class MainWindow : Adw.ApplicationWindow {
        private Gtk.Paned paned;
        private Gtk.Paned vertical_paned;
        private Gtk.Box console_drawer;
        private Vte.Terminal? vte_terminal = null;
        private int terminal_child_pid = 0;
        private Gtk.ScrolledWindow console_scrolled;
        private bool terminal_alive = false;
        private ulong terminal_child_exited_id = 0;
        private string? last_terminal_dir = null;
        private Gtk.Box command_bar;
        private Adw.ToastOverlay toast_overlay;
        public FilePanel left_panel { get; private set; }
        public FilePanel right_panel { get; private set; }
        public FilePanel active_panel { get; private set; }

        private Adw.HeaderBar header_bar;
        private Gtk.Label title_label;
        private Gtk.MenuButton drives_button;
        private DrivesPopover drives_popover;
        private Gtk.MenuButton operations_button;
        private Gtk.Label operations_label;
        private OperationsPopover operations_popover;
        private GenericArray<OperationProgressDialog> background_tasks;
        private Gtk.Entry cmd_entry;
        private Gtk.Box fn_bar;
        private Gtk.Label fn_f1_label;
        private Gtk.Label fn_f2_label;
        private Gtk.Label fn_f5_label;
        private Gtk.Label fn_f6_label;
        private bool fn_shift_active = false;
        private GenericArray<string> command_history;
        private int history_index = -1;
        private string saved_input = "";
        private Gtk.CssProvider theme_css_provider;
        private Gtk.CssProvider font_css_provider;
        private bool escape_sequence_pending = false;
        private uint escape_sequence_timeout_id = 0;
        private int saved_dual_paned_position = -1;
        private bool paned_resetting_half = false;
        private bool updating_vertical_paned = false;

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
            notify["is-active"].connect(() => {
                if (!is_active) {
                    update_function_bar_shift_state(false);
                }
            });

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

paned > separator {
    min-width: 6px;
    background-color: alpha(@borders, 0.25);
    transition: background-color 150ms ease;
}

paned > separator:hover {
    background-color: alpha(@accent_color, 0.5);
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
    padding: 6px 10px;
    min-height: 24px;
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

.fn-item {
    padding: 2px 4px;
    border-radius: 4px;
    transition: background-color 100ms ease-in-out;
}

.fn-item:hover {
    background-color: alpha(@accent_color, 0.15);
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

.thumbnail-grid-view {
    padding: 6px;
}

.thumbnail-img-box {
    border-radius: 6px;
    background-color: alpha(currentColor, 0.05);
    overflow: hidden;
}

.thumbnail-img-box.file-item-tagged {
    outline: 2px solid #f6d32d;
    outline-offset: 1px;
}
""";

        private const string SOLARIZED_DARK_CSS = """
@define-color accent_color #268bd2;
@define-color accent_bg_color #268bd2;
@define-color accent_fg_color #ffffff;
@define-color window_bg_color #002b36;
@define-color window_fg_color #839496;
@define-color view_bg_color #073642;
@define-color view_fg_color #93a1a1;
@define-color headerbar_bg_color #002b36;
@define-color headerbar_fg_color #839496;
@define-color headerbar_border_color alpha(#586e75, 0.5);
@define-color headerbar_backdrop_color #002b36;
@define-color card_bg_color #073642;
@define-color card_fg_color #93a1a1;
@define-color dialog_bg_color #002b36;
@define-color dialog_fg_color #839496;
@define-color popover_bg_color #073642;
@define-color popover_fg_color #93a1a1;
@define-color borders alpha(#586e75, 0.45);
@define-color secondary_color #586e75;
""";

        private const string SOLARIZED_LIGHT_CSS = """
@define-color accent_color #268bd2;
@define-color accent_bg_color #268bd2;
@define-color accent_fg_color #ffffff;
@define-color window_bg_color #fdf6e3;
@define-color window_fg_color #657b83;
@define-color view_bg_color #eee8d5;
@define-color view_fg_color #586e75;
@define-color headerbar_bg_color #fdf6e3;
@define-color headerbar_fg_color #657b83;
@define-color headerbar_border_color alpha(#93a1a1, 0.5);
@define-color headerbar_backdrop_color #fdf6e3;
@define-color card_bg_color #eee8d5;
@define-color card_fg_color #586e75;
@define-color dialog_bg_color #fdf6e3;
@define-color dialog_fg_color #657b83;
@define-color popover_bg_color #eee8d5;
@define-color popover_fg_color #586e75;
@define-color borders alpha(#93a1a1, 0.45);
@define-color secondary_color #93a1a1;
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

            theme_css_provider = new Gtk.CssProvider();
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                theme_css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 5
            );

            font_css_provider = new Gtk.CssProvider();
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                font_css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10
            );

            var settings = Gtk.Settings.get_for_display(Gdk.Display.get_default());
            if (settings != null) {
                settings.gtk_error_bell = false;
                settings.gtk_enable_event_sounds = false;
                settings.gtk_enable_input_feedback_sounds = false;
            }

            apply_app_theme();
            apply_font_styles();
        }

        public void apply_app_theme() {
            var config = ConfigManager.get_instance();
            var sm = Adw.StyleManager.get_default();
            string theme = config.app_theme.strip();

            if (theme == "light") {
                sm.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                if (theme_css_provider != null) {
                    theme_css_provider.load_from_string("");
                }
            } else if (theme == "dark") {
                sm.color_scheme = Adw.ColorScheme.FORCE_DARK;
                if (theme_css_provider != null) {
                    theme_css_provider.load_from_string("");
                }
            } else if (theme == "solarized-dark") {
                sm.color_scheme = Adw.ColorScheme.FORCE_DARK;
                if (theme_css_provider != null) {
                    theme_css_provider.load_from_string(SOLARIZED_DARK_CSS);
                }
            } else if (theme == "solarized-light") {
                sm.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                if (theme_css_provider != null) {
                    theme_css_provider.load_from_string(SOLARIZED_LIGHT_CSS);
                }
            } else {
                // "system" / default
                sm.color_scheme = Adw.ColorScheme.DEFAULT;
                if (theme_css_provider != null) {
                    theme_css_provider.load_from_string("");
                }
            }
        }

        public void apply_font_styles() {
            var config = ConfigManager.get_instance();
            int panel_font_size = config.panel_font_size > 0 ? config.panel_font_size : 11;

            // Status bar font size is 30% smaller than chosen panel font size (rounded)
            int status_font_size = (panel_font_size * 7 + 5) / 10;
            if (status_font_size < 7) {
                status_font_size = 7;
            }

            // Proportional vertical padding and minimum height calculation
            int pad_top = (status_font_size * 45 + 99) / 100;
            if (pad_top < 5) pad_top = 5;
            int pad_bottom = pad_top;

            int text_height = (status_font_size * 18 + 9) / 10;
            int min_bar_height = text_height + pad_top + pad_bottom + 2;

            string panel_style = ConfigManager.normalize_font_style(config.panel_font_style);
            int panel_weight = ConfigManager.clamp_font_weight(config.panel_font_weight);
            string css = """
.file-list-view {
    font-family: '%s', monospace;
    font-size: %dpt;
    font-weight: %d;
    font-style: %s;
}
.command-entry {
    font-family: '%s', monospace;
    font-size: %dpt;
    font-weight: %d;
    font-style: %s;
}
.panel-status-bar {
    font-family: '%s', monospace;
    font-size: %dpt;
    font-weight: %d;
    font-style: %s;
    padding: %dpx 10px %dpx 10px;
    min-height: %dpx;
}
""".printf(
                config.panel_font_name,
                panel_font_size,
                panel_weight,
                panel_style,
                config.panel_font_name,
                panel_font_size,
                panel_weight,
                panel_style,
                config.panel_font_name,
                status_font_size,
                panel_weight,
                panel_style,
                pad_top,
                pad_bottom,
                min_bar_height
            );

            font_css_provider.load_from_string(css);
        }

        private void build_ui() {
            var config = ConfigManager.get_instance();
            var root_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

            // Header Bar
            header_bar = new Adw.HeaderBar();
            title_label = new Gtk.Label(@"Vala Commander $(ConfigManager.get_version())");
            title_label.add_css_class("title");
            title_label.ellipsize = Pango.EllipsizeMode.START;
            title_label.tooltip_text = @"Vala Commander $(ConfigManager.get_version())";
            header_bar.title_widget = title_label;

            var log_button = new Gtk.Button.from_icon_name("text-x-generic-symbolic");
            log_button.tooltip_text = "View Application Log";
            log_button.focusable = false;
            log_button.clicked.connect(() => {
                open_application_log();
            });
            header_bar.pack_start(log_button);

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

            drives_popover = new DrivesPopover(this);

            drives_button = new Gtk.MenuButton();
            drives_button.icon_name = "drive-harddisk-symbolic";
            drives_button.always_show_arrow = false;
            drives_button.focusable = false;
            drives_button.tooltip_text = "Drives & Locations (Ctrl+F1)";
            drives_button.set_popover(drives_popover);
            drives_button.notify["active"].connect(() => {
                if (drives_button.active) {
                    drives_popover.populate_items(true);
                } else {
                    if (console_drawer.visible && vte_terminal != null) {
                        vte_terminal.grab_focus();
                    } else if (active_panel != null) {
                        active_panel.grab_focus_to_list();
                    }
                }
            });
            header_bar.pack_end(drives_button);

            background_tasks = new GenericArray<OperationProgressDialog>();
            operations_popover = new OperationsPopover();
            operations_popover.restore_requested.connect((task) => {
                restore_operation(task);
            });
            operations_popover.cancel_requested.connect((task) => {
                cancel_operation(task);
            });

            operations_button = new Gtk.MenuButton();
            operations_button.visible = false;
            operations_button.always_show_arrow = false;
            operations_button.focusable = false;
            operations_button.tooltip_text = "Background Operations";
            operations_button.add_css_class("operations-button");
            operations_button.set_popover(operations_popover);
            operations_button.notify["active"].connect(() => {
                if (operations_button.active) {
                    operations_popover.refresh_order();
                } else {
                    if (console_drawer.visible && vte_terminal != null) {
                        vte_terminal.grab_focus();
                    } else if (active_panel != null) {
                        active_panel.grab_focus_to_list();
                    }
                }
            });

            DriveQueueManager.get_instance().queue_changed.connect(() => {
                update_operations_button();
            });

            var vol_service = VolumeService.get_instance();
            vol_service.mount_pre_unmount_detected.connect((m) => {
                var root = m.get_root();
                if (root != null) {
                    handle_mount_removed(root);
                }
            });
            vol_service.mount_removed_detected.connect((m) => {
                var root = m.get_root();
                if (root != null) {
                    handle_mount_removed(root);
                }
            });

            var op_btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var op_icon = new Gtk.Image.from_icon_name("folder-download-symbolic");
            op_icon.pixel_size = 16;
            op_btn_box.append(op_icon);
            operations_label = new Gtk.Label("");
            op_btn_box.append(operations_label);
            operations_button.set_child(op_btn_box);

            header_bar.pack_end(operations_button);

            root_box.append(header_bar);

            // Dual Panes
            paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            paned.hexpand = true;
            paned.vexpand = true;
            paned.wide_handle = true;

            left_panel = new FilePanel(config.left_tabs, config.left_tab_titles, config.left_active_tab, config.left_brief_view, config.show_hidden, config.left_sort_cols, config.left_sort_orders, config.left_view_modes, config.left_pinned_tabs);
            right_panel = new FilePanel(config.right_tabs, config.right_tab_titles, config.right_active_tab, config.right_brief_view, config.show_hidden, config.right_sort_cols, config.right_sort_orders, config.right_view_modes, config.right_pinned_tabs);

            left_panel.panel_activated.connect(on_panel_activated);
            right_panel.panel_activated.connect(on_panel_activated);

            left_panel.directory_changed.connect(on_panel_directory_changed);
            right_panel.directory_changed.connect(on_panel_directory_changed);

            left_panel.command_char_typed.connect(on_command_char_typed);
            right_panel.command_char_typed.connect(on_command_char_typed);

            left_panel.error_occurred.connect(show_error_dialog);
            right_panel.error_occurred.connect(show_error_dialog);

            left_panel.tab_sort_changed.connect(() => {
                save_state();
            });
            right_panel.tab_sort_changed.connect(() => {
                save_state();
            });

            left_panel.tabs_state_changed.connect(() => {
                save_state();
            });
            right_panel.tabs_state_changed.connect(() => {
                save_state();
            });

            left_panel.view_mode_changed.connect((p) => {
                update_super_view_layout();
                update_window_title();
            });
            right_panel.view_mode_changed.connect((p) => {
                update_super_view_layout();
                update_window_title();
            });

            left_panel.toggle_hidden_requested.connect(() => {
                toggle_show_hidden();
            });
            right_panel.toggle_hidden_requested.connect(() => {
                toggle_show_hidden();
            });

            left_panel.restore_requested.connect(on_panel_restore_requested);
            right_panel.restore_requested.connect(on_panel_restore_requested);

            left_panel.empty_trash_requested.connect(on_panel_empty_trash_requested);
            right_panel.empty_trash_requested.connect(on_panel_empty_trash_requested);

            left_panel.restore_item_requested.connect(on_panel_restore_item_requested);
            right_panel.restore_item_requested.connect(on_panel_restore_item_requested);

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

            // Reset paned position to 50/50 on double click on separator handle
            var handle_gesture = new Gtk.GestureClick();
            handle_gesture.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
            handle_gesture.set_button(0);
            handle_gesture.pressed.connect((n_press, x, y) => {
                if (n_press == 2) {
                    handle_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
                    trigger_paned_reset_to_half();
                }
            });

            // Find the separator child widget of paned
            var child = paned.get_first_child();
            while (child != null) {
                if (child.get_css_name() == "separator") {
                    child.add_controller(handle_gesture);
                    break;
                }
                child = child.get_next_sibling();
            }

            // Also attach CAPTURE controller on paned itself as fallback
            var paned_fallback_gesture = new Gtk.GestureClick();
            paned_fallback_gesture.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
            paned_fallback_gesture.set_button(0);
            paned_fallback_gesture.pressed.connect((n_press, x, y) => {
                if (n_press == 2) {
                    int pos = paned.position;
                    // Check if click occurred within handle width (around current paned position, handle is 8-16px wide)
                    if (Math.fabs(x - pos) <= 24) {
                        paned_fallback_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
                        trigger_paned_reset_to_half();
                    }
                }
            });
            paned.add_controller(paned_fallback_gesture);

            // Connect to paned's internal drag controllers to cancel them when resetting
            var controllers = paned.observe_controllers();
            for (uint i = 0; i < controllers.get_n_items(); i++) {
                var c = controllers.get_item(i);
                if (c is Gtk.GestureDrag) {
                    var dg = (Gtk.GestureDrag) c;
                    dg.drag_update.connect(() => {
                        if (paned_resetting_half) {
                            dg.set_state(Gtk.EventSequenceState.DENIED);
                        }
                    });
                    dg.drag_end.connect(() => {
                        if (paned_resetting_half) {
                            dg.set_state(Gtk.EventSequenceState.DENIED);
                            reset_paned_to_half();
                        }
                    });
                }
            }

            // Vertical paned splitting dual file panels (top) and console output drawer (bottom)
            vertical_paned = new Gtk.Paned(Gtk.Orientation.VERTICAL);
            vertical_paned.hexpand = true;
            vertical_paned.vexpand = true;
            vertical_paned.wide_handle = true;

            vertical_paned.start_child = paned;

            // Build console drawer
            build_console_drawer();
            vertical_paned.end_child = console_drawer;

            // Track vertical paned position changes
            vertical_paned.notify["position"].connect(() => {
                if (!updating_vertical_paned && console_drawer.visible) {
                    int total_h = vertical_paned.get_height();
                    int pos = vertical_paned.position;
                    if (total_h > 0 && pos > 0 && total_h > pos) {
                        int ch = total_h - pos;
                        if (ch >= 80 && ch <= 1600) {
                            config.console_height = ch;
                        }
                    }
                }
            });

            root_box.append(vertical_paned);

            // Bottom MC-style Command Line Bar
            build_command_bar(root_box);

            // Bottom MC-style Function Key Bar
            build_function_bar(root_box);

            toast_overlay = new Adw.ToastOverlay();
            toast_overlay.child = root_box;
            content = toast_overlay;

            setup_keyboard_shortcuts(root_box);
        }

        private void build_console_drawer() {
            console_drawer = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            console_drawer.add_css_class("console-drawer");
            console_drawer.visible = false;

            // Console header bar
            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            header.add_css_class("console-header");

            var icon = new Gtk.Image.from_icon_name("utilities-terminal-symbolic");
            icon.pixel_size = 14;
            header.append(icon);

            var title = new Gtk.Label("Terminal");
            title.add_css_class("heading");
            title.halign = Gtk.Align.START;
            header.append(title);

            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            header.append(spacer);

            var sync_btn = new Gtk.Button.from_icon_name("folder-symbolic");
            sync_btn.tooltip_text = "Change directory to active pane";
            sync_btn.add_css_class("flat");
            sync_btn.clicked.connect(() => {
                if (active_panel != null && active_panel.current_directory != null) {
                    string? p = active_panel.current_directory.get_path();
                    if (p != null) {
                        string escaped = p.replace("'", "'\\''");
                        if (vte_terminal != null && terminal_alive) {
                            vte_terminal.feed_child(@"cd '$escaped'\n".data);
                            last_terminal_dir = p;
                        }
                    }
                }
                if (vte_terminal != null) {
                    vte_terminal.grab_focus();
                }
            });
            header.append(sync_btn);

            var restart_btn = new Gtk.Button.from_icon_name("system-shutdown-symbolic");
            restart_btn.tooltip_text = "Kill hung terminal and restart";
            restart_btn.add_css_class("flat");
            restart_btn.clicked.connect(() => {
                kill_and_restart_terminal();
            });
            header.append(restart_btn);

            var clear_btn = new Gtk.Button.from_icon_name("edit-clear-symbolic");
            clear_btn.tooltip_text = "Clear terminal";
            clear_btn.add_css_class("flat");
            clear_btn.clicked.connect(() => {
                if (vte_terminal != null) {
                    vte_terminal.reset(true, true);
                    vte_terminal.feed_child("\x0c".data);
                    vte_terminal.grab_focus();
                }
            });
            header.append(clear_btn);

            var close_btn = new Gtk.Button.from_icon_name("window-close-symbolic");
            close_btn.tooltip_text = "Hide terminal (Ctrl+O or Ctrl+~)";
            close_btn.add_css_class("flat");
            close_btn.clicked.connect(() => {
                set_console_visible(false);
            });
            header.append(close_btn);

            console_drawer.append(header);

            // Scrolled window container for VTE terminal
            console_scrolled = new Gtk.ScrolledWindow();
            console_scrolled.hexpand = true;
            console_scrolled.vexpand = true;
            console_scrolled.min_content_height = 80;

            console_drawer.append(console_scrolled);
        }

        public void toggle_console_drawer() {
            set_console_visible(!console_drawer.visible);
        }

        public void set_console_visible(bool visible) {
            if (console_drawer.visible == visible) {
                if (visible && vte_terminal != null) {
                    vte_terminal.grab_focus();
                }
                return;
            }

            console_drawer.visible = visible;
            if (command_bar != null) {
                command_bar.visible = !visible;
            }

            if (visible) {
                string? cwd = null;
                if (active_panel != null && active_panel.current_directory != null) {
                    cwd = resolve_local_path_for_file(active_panel.current_directory);
                }
                if (!terminal_alive || vte_terminal == null) {
                    spawn_terminal(cwd);
                } else if (cwd != null) {
                    sync_terminal_directory(cwd);
                }

                apply_console_paned_position();

                GLib.Idle.add(() => {
                    if (vte_terminal != null && console_drawer.visible) {
                        vte_terminal.grab_focus();
                    }
                    return GLib.Source.REMOVE;
                });
            } else {
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) {
                    active_panel.grab_focus_to_list();
                }
            }
        }

        public static string? resolve_local_path_for_file(File? file) {
            if (file == null) return null;

            if (file.get_uri_scheme() == "archive") {
                string? arc_path;
                string? in_path;
                if (ArchiveTreeService.split_archive_uri(file.get_uri(), out arc_path, out in_path)) {
                    return Path.get_dirname(arc_path);
                }
                return null;
            }

            string? local_path = file.get_path();
            if (local_path != null && local_path.length > 0) {
                return local_path;
            }

            // If file has no direct local path (e.g. GVfs mounts sftp://, dav://, smb://),
            // check if GVfs FUSE daemon mapped it to /run/user/<UID>/gvfs
            string uri = file.get_uri();
            uint uid = (uint) Posix.getuid();
            string gvfs_dir = @"/run/user/$uid/gvfs";
            if (!FileUtils.test(gvfs_dir, FileTest.IS_DIR)) {
                return null;
            }

            var vm = VolumeMonitor.get();
            var mounts = vm.get_mounts();
            foreach (var m in mounts) {
                var root = m.get_root();
                if (root == null) continue;
                string root_uri = root.get_uri();

                if (uri == root_uri || uri.has_prefix(root_uri + "/") || uri.has_prefix(root_uri)) {
                    string rel_path = "";
                    if (uri.length > root_uri.length) {
                        rel_path = uri.substring(root_uri.length);
                        if (rel_path.has_prefix("/")) rel_path = rel_path.substring(1);
                    }

                    try {
                        var dir = Dir.open(gvfs_dir, 0);
                        string? entry_name = null;
                        while ((entry_name = dir.read_name()) != null) {
                            string mount_base = Path.build_filename(gvfs_dir, entry_name);
                            string cand_path = mount_base;
                            if (rel_path.length > 0) {
                                cand_path = Path.build_filename(mount_base, Uri.unescape_string(rel_path));
                            }
                            if (FileUtils.test(cand_path, FileTest.EXISTS)) {
                                return cand_path;
                            }
                        }
                    } catch (Error e) {}
                }
            }
            return null;
        }

        private void apply_console_paned_position() {
            int total_h = vertical_paned.get_height();
            if (total_h > 150) {
                var config = ConfigManager.get_instance();
                int ch = config.console_height > 0 ? config.console_height : 400;
                int target_pos = int.max(80, total_h - ch);
                updating_vertical_paned = true;
                vertical_paned.position = target_pos;
                updating_vertical_paned = false;
            }
        }

        private bool is_terminal_at_prompt() {
            if (vte_terminal == null || !terminal_alive || terminal_child_pid <= 1) return false;
            try {
                string stat_content;
                FileUtils.get_contents(@"/proc/$terminal_child_pid/stat", out stat_content);
                int idx = stat_content.last_index_of(")");
                if (idx < 0) return true;
                string rest = stat_content.substring(idx + 2);
                string[] parts = rest.split(" ");
                // in rest: [0]=state, [1]=ppid, [2]=pgrp, [3]=session, [4]=tty_nr, [5]=tpgid
                if (parts.length < 6) return true;
                int pgrp = int.parse(parts[2]);
                int tpgid = int.parse(parts[5]);

                if (tpgid <= 0 || tpgid == pgrp || tpgid == terminal_child_pid) {
                    return true;
                }

                string comm;
                FileUtils.get_contents(@"/proc/$tpgid/comm", out comm);
                string trimmed = comm.strip();
                return (trimmed == "bash" || trimmed == "zsh" || trimmed == "sh" || trimmed == "fish");
            } catch (Error e) {
                return true;
            }
        }

        private void sync_terminal_directory(string target_dir) {
            if (vte_terminal == null || !terminal_alive || terminal_child_pid <= 1) {
                spawn_terminal(target_dir);
                return;
            }

            string? shell_cwd = null;
            try {
                shell_cwd = FileUtils.read_link(@"/proc/$terminal_child_pid/cwd");
            } catch (Error e) {}

            if (shell_cwd != null && shell_cwd == target_dir) {
                last_terminal_dir = target_dir;
                return;
            }

            if (is_terminal_at_prompt()) {
                string escaped = target_dir.replace("'", "'\\''");
                vte_terminal.feed_child(@"cd '$escaped'\n".data);
                last_terminal_dir = target_dir;
            }
        }

        private void spawn_terminal(string? working_dir) {
            string? cwd = working_dir;
            if (cwd == null || cwd.length == 0) {
                if (active_panel != null && active_panel.current_directory != null) {
                    cwd = resolve_local_path_for_file(active_panel.current_directory);
                }
            }
            if (cwd == null || cwd.length == 0) {
                cwd = Environment.get_home_dir();
            }

            if (vte_terminal == null) {
                vte_terminal = new Vte.Terminal();
                vte_terminal.hexpand = true;
                vte_terminal.vexpand = true;
                vte_terminal.set_audible_bell(false);
                console_scrolled.set_child(vte_terminal);

                terminal_child_exited_id = vte_terminal.child_exited.connect((status) => {
                    terminal_alive = false;
                    terminal_child_pid = 0;
                    if (console_drawer.visible) {
                        set_console_visible(false);
                    }
                });
            }

            apply_terminal_font();
            apply_terminal_theme();
            var config = ConfigManager.get_instance();
            vte_terminal.set_scrollback_lines(config.console_history_limit > 0 ? config.console_history_limit : 2000);

            string shell_bin = config.command_shell.strip();
            if (shell_bin.length == 0 || Environment.find_program_in_path(shell_bin) == null) {
                shell_bin = Environment.get_variable("SHELL");
                if (shell_bin == null || shell_bin.length == 0) {
                    shell_bin = "/bin/bash";
                }
            }

            string[] argv = { shell_bin, "-i" };
            string[] env = GLib.Environ.get();
            string? discovered_agent = RemoteMount.discover_agent(0);
            if (discovered_agent != null) {
                env = GLib.Environ.set_variable(env, "SSH_AUTH_SOCK", discovered_agent, true);
            }
            env = GLib.Environ.set_variable(env, "TERM", "xterm-256color", true);
            env = GLib.Environ.set_variable(env, "COLORTERM", "truecolor", true);

            vte_terminal.spawn_async(
                Vte.PtyFlags.DEFAULT,
                cwd,
                argv,
                env,
                GLib.SpawnFlags.SEARCH_PATH,
                null,
                -1,
                null,
                (term, pid, err) => {
                    if (err == null) {
                        terminal_child_pid = (int) pid;
                    }
                }
            );
            terminal_alive = true;
            last_terminal_dir = cwd;
        }

        private void kill_terminal_processes() {
            int pid = terminal_child_pid;
            if (pid <= 1 || pid == (int) Posix.getpid()) {
                return;
            }

            // 1. Terminate foreground process group if different from shell/vcmd
            if (vte_terminal != null) {
                var pty = vte_terminal.get_pty();
                if (pty != null) {
                    int fd = pty.get_fd();
                    if (fd >= 0) {
                        long fg_pgrp = (long) Posix.tcgetpgrp(fd);
                        if (fg_pgrp > 1 && fg_pgrp != (long) Posix.getpgrp() && fg_pgrp != (long) Posix.getpid()) {
                            Posix.kill((Posix.pid_t) (-fg_pgrp), Posix.Signal.KILL);
                            Posix.kill((Posix.pid_t) fg_pgrp, Posix.Signal.KILL);
                        }
                    }
                }
            }

            // 2. Terminate all child and session processes in /proc
            kill_session_processes(pid);

            // 3. Terminate the shell process group and the shell itself
            Posix.kill((Posix.pid_t) (-pid), Posix.Signal.KILL);
            Posix.kill((Posix.pid_t) pid, Posix.Signal.KILL);
        }

        private void kill_session_processes(int session_leader_pid) {
            try {
                var dir = Dir.open("/proc", 0);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    int p = int.parse(name);
                    if (p <= 1 || p == (int) Posix.getpid() || p == session_leader_pid) {
                        continue;
                    }

                    string stat_content;
                    if (FileUtils.get_contents(@"/proc/$name/stat", out stat_content)) {
                        int close_paren = stat_content.last_index_of(")");
                        if (close_paren > 0 && close_paren + 2 < stat_content.length) {
                            string rest = stat_content.substring(close_paren + 2);
                            string[] fields = rest.split(" ");
                            if (fields.length >= 4) {
                                int ppid = int.parse(fields[1]);
                                int sid = int.parse(fields[3]);
                                if (sid == session_leader_pid || ppid == session_leader_pid) {
                                    Posix.kill((Posix.pid_t) p, Posix.Signal.KILL);
                                }
                            }
                        }
                    }
                }
            } catch (Error e) {
                // Ignore /proc read errors for transient processes
            }
        }

        public void kill_and_restart_terminal() {
            kill_terminal_processes();
            terminal_child_pid = 0;
            terminal_alive = false;

            if (vte_terminal != null) {
                if (terminal_child_exited_id != 0) {
                    vte_terminal.disconnect(terminal_child_exited_id);
                    terminal_child_exited_id = 0;
                }
                console_scrolled.set_child(null);
                vte_terminal = null;
            }

            string? cwd = null;
            if (active_panel != null && active_panel.current_directory != null) {
                cwd = active_panel.current_directory.get_path();
            }

            spawn_terminal(cwd);
            show_command_toast("Terminal restarted");

            GLib.Idle.add(() => {
                if (vte_terminal != null && console_drawer.visible) {
                    vte_terminal.grab_focus();
                }
                return GLib.Source.REMOVE;
            });
        }

        public void apply_terminal_font() {
            if (vte_terminal == null) return;
            var config = ConfigManager.get_instance();
            var desc = ConfigManager.make_font_description(
                config.terminal_font_name,
                config.terminal_font_size,
                config.terminal_font_weight,
                config.terminal_font_style
            );
            vte_terminal.set_font(desc);
        }

        public void apply_terminal_theme() {
            if (vte_terminal == null) return;
            var config = ConfigManager.get_instance();
            string theme = config.terminal_color_theme.strip();

            if (theme == "dracula" || theme == "solarized-dark") {
                string[] hex_palette = {
                    "#21222c", "#ff3333", "#50fa7b", "#f1fa8c",
                    "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                    "#6272a4", "#ff5555", "#69ff94", "#ffffa5",
                    "#d6acff", "#ff92df", "#a4ffff", "#ffffff"
                };
                Gdk.RGBA[] palette = new Gdk.RGBA[16];
                for (int i = 0; i < 16; i++) {
                    Gdk.RGBA c = {};
                    c.parse(hex_palette[i]);
                    palette[i] = c;
                }
                Gdk.RGBA fg = {};
                fg.parse("#f8f8f2");
                Gdk.RGBA bg = {};
                bg.parse("#282a36");
                Gdk.RGBA cur = {};
                cur.parse("#f8f8f2");
                Gdk.RGBA sel_fg = {};
                sel_fg.parse("#ffffff");
                Gdk.RGBA sel_bg = {};
                sel_bg.parse("#44475a");
                vte_terminal.set_colors(fg, bg, palette);
                vte_terminal.set_color_cursor(cur);
                vte_terminal.set_color_cursor_foreground(bg);
                vte_terminal.set_color_highlight(sel_bg);
                vte_terminal.set_color_highlight_foreground(sel_fg);
            } else if (theme == "tango" || theme == "solarized-light") {
                string[] hex_palette = {
                    "#2e3436", "#cc0000", "#4e9a06", "#c4a000",
                    "#3465a4", "#75507b", "#06989a", "#d3d7cf",
                    "#555753", "#ef2929", "#8ae234", "#fce94f",
                    "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
                };
                Gdk.RGBA[] palette = new Gdk.RGBA[16];
                for (int i = 0; i < 16; i++) {
                    Gdk.RGBA c = {};
                    c.parse(hex_palette[i]);
                    palette[i] = c;
                }
                Gdk.RGBA fg = {};
                fg.parse("#eeeeec");
                Gdk.RGBA bg = {};
                bg.parse("#300a24");
                Gdk.RGBA cur = {};
                cur.parse("#bbbbbb");
                Gdk.RGBA cur_fg = {};
                cur_fg.parse("#ffffff");
                Gdk.RGBA sel_fg = {};
                sel_fg.parse("#300a24");
                Gdk.RGBA sel_bg = {};
                sel_bg.parse("#eeeeec");
                vte_terminal.set_colors(fg, bg, palette);
                vte_terminal.set_color_cursor(cur);
                vte_terminal.set_color_cursor_foreground(cur_fg);
                vte_terminal.set_color_highlight(sel_bg);
                vte_terminal.set_color_highlight_foreground(sel_fg);
            } else if (theme == "green-on-black") {
                string[] hex_palette = {
                    "#000000", "#aa0000", "#00aa00", "#aa5500",
                    "#0000aa", "#aa00aa", "#00aaaa", "#aaaaaa",
                    "#555555", "#ff5555", "#55ff55", "#ffff55",
                    "#5555ff", "#ff55ff", "#55ffff", "#ffffff"
                };
                Gdk.RGBA[] palette = new Gdk.RGBA[16];
                for (int i = 0; i < 16; i++) {
                    Gdk.RGBA c = {};
                    c.parse(hex_palette[i]);
                    palette[i] = c;
                }
                Gdk.RGBA fg = {};
                fg.parse("#20c20e");
                Gdk.RGBA bg = {};
                bg.parse("#000000");
                Gdk.RGBA cur = {};
                cur.parse("#20c20e");
                vte_terminal.set_colors(fg, bg, palette);
                vte_terminal.set_color_cursor(cur);
                vte_terminal.set_color_cursor_foreground(null);
                vte_terminal.set_color_highlight(null);
                vte_terminal.set_color_highlight_foreground(null);
            } else if (theme == "ansi-1987") {
                string[] hex_palette = {
                    "#000000", "#aa0000", "#00aa00", "#aa5500",
                    "#004499", "#aa00aa", "#00aaaa", "#aaaaaa",
                    "#555555", "#ff5555", "#55ff55", "#ffff55",
                    "#5555ff", "#ff55ff", "#55ffff", "#ffffff"
                };
                Gdk.RGBA[] palette = new Gdk.RGBA[16];
                for (int i = 0; i < 16; i++) {
                    Gdk.RGBA c = {};
                    c.parse(hex_palette[i]);
                    palette[i] = c;
                }
                Gdk.RGBA fg = {};
                fg.parse("#50aa4b");
                Gdk.RGBA bg = {};
                bg.parse("#000000");
                Gdk.RGBA cur = {};
                cur.parse("#50aa4b");
                Gdk.RGBA cur_fg = {};
                cur_fg.parse("#aaaaaa");
                Gdk.RGBA sel_fg = {};
                sel_fg.parse("#000000");
                Gdk.RGBA sel_bg = {};
                sel_bg.parse("#aaaaaa");
                vte_terminal.set_colors(fg, bg, palette);
                vte_terminal.set_color_cursor(cur);
                vte_terminal.set_color_cursor_foreground(cur_fg);
                vte_terminal.set_color_highlight(sel_bg);
                vte_terminal.set_color_highlight_foreground(sel_fg);
            } else {
                vte_terminal.set_colors(null, null, null);
                vte_terminal.set_color_cursor(null);
                vte_terminal.set_color_cursor_foreground(null);
                vte_terminal.set_color_highlight(null);
                vte_terminal.set_color_highlight_foreground(null);
            }
        }

        private void build_command_bar(Gtk.Box parent_box) {
            command_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
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

        private delegate void FnItemCallback();

        private void build_function_bar(Gtk.Box parent_box) {
            var config = ConfigManager.get_instance();
            fn_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            fn_bar.homogeneous = true;
            fn_bar.add_css_class("function-bar");
            fn_bar.visible = config.show_function_bar;

            Gtk.Label dummy;
            fn_bar.append(create_fn_item("F1", "Help", out fn_f1_label, () => { on_fn_f1_clicked(); }));
            fn_bar.append(create_fn_item("F2", "Connect", out fn_f2_label, () => { on_fn_f2_clicked(); }));
            fn_bar.append(create_fn_item("F3", "View", out dummy, () => { on_f3_view(); }));
            fn_bar.append(create_fn_item("F4", "Edit", out dummy, () => { on_f4_edit(); }));
            fn_bar.append(create_fn_item("F5", "Copy", out fn_f5_label, () => { on_fn_f5_clicked(); }));
            fn_bar.append(create_fn_item("F6", "Move", out fn_f6_label, () => { on_fn_f6_clicked(); }));
            fn_bar.append(create_fn_item("F7", "Mkdir", out dummy, () => { on_f7_mkdir(); }));
            fn_bar.append(create_fn_item("F8", "Delete", out dummy, () => { on_delete(fn_shift_active); }));
            fn_bar.append(create_fn_item("F10", "Quit", out dummy, () => { close(); }));

            parent_box.append(fn_bar);
        }

        private Gtk.Widget create_fn_item(string key_badge, string label_text, out Gtk.Label out_label, owned FnItemCallback? on_click = null) {
            var item_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            item_box.add_css_class("fn-item");
            item_box.hexpand = true;

            var content_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            content_box.halign = Gtk.Align.CENTER;
            content_box.hexpand = true;

            var badge = new Gtk.Label(key_badge);
            badge.add_css_class("fn-key-badge");

            var lbl = new Gtk.Label(label_text);
            lbl.add_css_class("fn-key-label");
            out_label = lbl;

            content_box.append(badge);
            content_box.append(lbl);
            item_box.append(content_box);

            if (on_click != null) {
                var gesture = new Gtk.GestureClick();
                gesture.pressed.connect(() => {
                    on_click();
                });
                item_box.add_controller(gesture);
            }

            return item_box;
        }

        private void on_fn_f1_clicked() {
            if (fn_shift_active) {
                show_about_dialog(this);
            } else {
                ShortcutsDialog.show(this);
            }
        }

        private void on_fn_f2_clicked() {
            if (fn_shift_active) {
                on_pack_archive();
            } else if (active_panel != null) {
                ConnectDialog.show(this, active_panel);
            }
        }

        private void on_fn_f5_clicked() {
            if (fn_shift_active) {
                on_shift_f5_symlink();
            } else {
                on_f5_copy();
            }
        }

        private void on_fn_f6_clicked() {
            if (active_panel != null && active_panel.is_trash_location) {
                prompt_restore_trash(active_panel);
            } else if (fn_shift_active) {
                on_shift_f6_rename();
            } else {
                on_f6_move();
            }
        }

        private void update_function_bar_shift_state(bool shift_pressed) {
            if (fn_shift_active == shift_pressed) return;
            fn_shift_active = shift_pressed;
            if (fn_f1_label != null) {
                fn_f1_label.label = shift_pressed ? "About" : "Help";
            }
            if (fn_f2_label != null) {
                fn_f2_label.label = shift_pressed ? "Pack" : "Connect";
            }
            if (fn_f5_label != null) {
                fn_f5_label.label = shift_pressed ? "Symlink" : "Copy";
            }
        }

        private void update_function_bar_trash_state() {
            if (fn_f6_label != null) {
                bool in_trash = (active_panel != null && active_panel.is_trash_location);
                fn_f6_label.label = in_trash ? "Restore" : "Move";
            }
        }

        private void setup_keyboard_shortcuts(Gtk.Widget target_widget) {
            var key_controller = new Gtk.EventControllerKey();
            key_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                if (fn_bar != null && fn_bar.visible) {
                    if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R) {
                        update_function_bar_shift_state(true);
                        return Gdk.EVENT_PROPAGATE;
                    } else if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        update_function_bar_shift_state(true);
                    } else {
                        update_function_bar_shift_state(false);
                    }
                }

                uint latin_key = KeyUtils.to_latin(keyval, keycode);

                // When terminal drawer is visible, lock focus & inputs inside terminal except for toggle/close
                if (console_drawer.visible) {
                    bool is_tilde = (keyval == Gdk.Key.grave || keyval == Gdk.Key.asciitilde || latin_key == Gdk.Key.grave || latin_key == Gdk.Key.asciitilde);
                    if (((latin_key == Gdk.Key.o && (state & Gdk.ModifierType.SHIFT_MASK) == 0) || is_tilde) &&
                        (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                        (state & Gdk.ModifierType.ALT_MASK) == 0) {
                        set_console_visible(false);
                        return Gdk.EVENT_STOP;
                    }

                    // Ctrl+Shift+C: copy terminal selection
                    if (latin_key == Gdk.Key.c && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                        if (vte_terminal != null) vte_terminal.copy_clipboard_format(Vte.Format.TEXT);
                        return Gdk.EVENT_STOP;
                    }

                    // Ctrl+Shift+V: paste from clipboard
                    if (latin_key == Gdk.Key.v && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                        if (vte_terminal != null) vte_terminal.paste_clipboard();
                        return Gdk.EVENT_STOP;
                    }

                    // Shift+F1: About
                    if (keyval == Gdk.Key.F1 && (state & Gdk.ModifierType.SHIFT_MASK) != 0 && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                        show_about_dialog(this);
                        return Gdk.EVENT_STOP;
                    }

                    // Ctrl+F1: Drives & Locations
                    if (keyval == Gdk.Key.F1 && (state & Gdk.ModifierType.CONTROL_MASK) != 0 && (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                        toggle_drives_menu();
                        return Gdk.EVENT_STOP;
                    }

                    if (keyval == Gdk.Key.F2 && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                        if (active_panel != null) {
                            ConnectDialog.show(this, active_panel);
                        }
                        return Gdk.EVENT_STOP;
                    }

                    // Alt+F7: file search, even while the terminal has focus
                    if (keyval == Gdk.Key.F7 && (state & Gdk.ModifierType.ALT_MASK) != 0) {
                        show_file_search();
                        return Gdk.EVENT_STOP;
                    }

                    // All other keys pass straight to Vte.Terminal without being intercepted
                    return Gdk.EVENT_PROPAGATE;
                }

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

                // Ctrl+\: Directory Bookmarks / Hotlist (Midnight Commander style)
                if ((latin_key == Gdk.Key.backslash || keyval == Gdk.Key.backslash) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (active_panel != null) {
                        BookmarksDialog.show(this, active_panel);
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+R: refresh directory of active panel (Midnight Commander style)
                if ((latin_key == Gdk.Key.r || keyval == Gdk.Key.r || keyval == Gdk.Key.R) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (active_panel != null) {
                        active_panel.refresh();
                    }
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

                // Ctrl+U: Swap panels (Midnight Commander / Total Commander style)
                if ((latin_key == Gdk.Key.u || keyval == Gdk.Key.u || keyval == Gdk.Key.U) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    on_ctrl_u_swap_panels();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+B: Background Operations & Queue
                if ((latin_key == Gdk.Key.b || keyval == Gdk.Key.b || keyval == Gdk.Key.B) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (cmd_entry.has_focus && cmd_entry.text.length > 0) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    toggle_operations_menu();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Shift+O: Open selected file with...
                if (latin_key == Gdk.Key.o &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & Gdk.ModifierType.SHIFT_MASK) != 0 &&
                    (state & Gdk.ModifierType.ALT_MASK) == 0) {
                    if (active_panel != null) {
                        active_panel.open_selected_with_dialog();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+O or Ctrl+~ / Ctrl+` : Toggle Console Output Drawer (Midnight Commander / IDE style)
                bool is_tilde_grave = (keyval == Gdk.Key.grave || keyval == Gdk.Key.asciitilde || latin_key == Gdk.Key.grave || latin_key == Gdk.Key.asciitilde);
                if (((latin_key == Gdk.Key.o && (state & Gdk.ModifierType.SHIFT_MASK) == 0) || is_tilde_grave) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & Gdk.ModifierType.ALT_MASK) == 0) {
                    toggle_console_drawer();
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

                // Ctrl+Shift+P: toggle pin on current tab
                if (latin_key == Gdk.Key.p && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                    if (active_panel != null) {
                        active_panel.toggle_current_tab_pinned();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Alt+T: cycle view mode (Brief -> Detailed -> Super Detailed) for active panel
                if (latin_key == Gdk.Key.t && (state & Gdk.ModifierType.ALT_MASK) != 0) {
                    if (active_panel != null) {
                        active_panel.toggle_view_mode();
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl++ or Ctrl+= : increase brief view column width or grid zoom
                if ((keyval == Gdk.Key.plus || keyval == Gdk.Key.equal || keyval == Gdk.Key.KP_Add) && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (active_panel != null && active_panel.view_mode == PanelViewMode.GRID) {
                        active_panel.zoom_in_grid();
                    } else {
                        var config = ConfigManager.get_instance();
                        if (config.brief_column_width < 800) {
                            config.brief_column_width = int.min(800, config.brief_column_width + 10);
                            config.save();
                            apply_preferences();
                        }
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+- : decrease brief view column width or grid zoom
                if ((keyval == Gdk.Key.minus || keyval == Gdk.Key.KP_Subtract) && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (active_panel != null && active_panel.view_mode == PanelViewMode.GRID) {
                        active_panel.zoom_out_grid();
                    } else {
                        var config = ConfigManager.get_instance();
                        if (config.brief_column_width > 100) {
                            config.brief_column_width = int.max(100, config.brief_column_width - 10);
                            config.save();
                            apply_preferences();
                        }
                    }
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+0 : reset grid zoom
                if ((keyval == Gdk.Key.@0 || keyval == Gdk.Key.KP_0) && 
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (active_panel != null && active_panel.view_mode == PanelViewMode.GRID) {
                        active_panel.zoom_reset_grid();
                        return Gdk.EVENT_STOP;
                    }
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

                // Shift+F1: About Vala Commander
                if (keyval == Gdk.Key.F1 && (state & Gdk.ModifierType.SHIFT_MASK) != 0 && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    show_about_dialog(this);
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+F1: Drives & Locations
                if (keyval == Gdk.Key.F1 && (state & Gdk.ModifierType.CONTROL_MASK) != 0 && (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    toggle_drives_menu();
                    return Gdk.EVENT_STOP;
                }

                // F1: show Shortcuts Dialog
                if (keyval == Gdk.Key.F1 && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    ShortcutsDialog.show(this);
                    return Gdk.EVENT_STOP;
                }

                // Shift+F2: Pack / Compress Selected Files
                if (keyval == Gdk.Key.F2 && (state & Gdk.ModifierType.SHIFT_MASK) != 0 && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    on_pack_archive();
                    return Gdk.EVENT_STOP;
                }

                // F2: connect to a remote server
                if (keyval == Gdk.Key.F2 && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (active_panel != null) {
                        ConnectDialog.show(this, active_panel);
                    }
                    return Gdk.EVENT_STOP;
                }

                // F3: View
                if (keyval == Gdk.Key.F3) {
                    on_f3_view();
                    return Gdk.EVENT_STOP;
                }

                // F4: Edit
                if (keyval == Gdk.Key.F4) {
                    on_f4_edit();
                    return Gdk.EVENT_STOP;
                }

                // F5: Copy (or Shift+F5: Symlink)
                if (keyval == Gdk.Key.F5) {
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        on_shift_f5_symlink();
                    } else {
                        on_f5_copy();
                    }
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

                // F7: Mkdir; Alt+F7: file search
                if (keyval == Gdk.Key.F7) {
                    if ((state & Gdk.ModifierType.ALT_MASK) != 0) {
                        show_file_search();
                    } else if ((state & Gdk.ModifierType.CONTROL_MASK) == 0) {
                        on_f7_mkdir();
                    } else {
                        return Gdk.EVENT_PROPAGATE;
                    }
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

            key_controller.modifiers.connect((state) => {
                if (fn_bar != null && fn_bar.visible) {
                    update_function_bar_shift_state((state & Gdk.ModifierType.SHIFT_MASK) != 0);
                }
                return Gdk.EVENT_PROPAGATE;
            });

            key_controller.key_released.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R) {
                    update_function_bar_shift_state(false);
                }
            });

            target_widget.add_controller(key_controller);
        }

        private void on_panel_activated(FilePanel panel) {
            activate_panel(panel, false);
        }

        private void on_panel_directory_changed(File new_dir) {
            update_window_title();
            update_function_bar_trash_state();
            if (console_drawer.visible && active_panel != null && active_panel.current_directory != null) {
                string? p = resolve_local_path_for_file(active_panel.current_directory);
                if (p != null) {
                    sync_terminal_directory(p);
                }
            }
        }

        private void update_window_title() {
            if (title_label == null) return;
            string ver = ConfigManager.get_version();
            string? cur_path = null;
            if (active_panel != null && active_panel.current_directory != null) {
                var dir = active_panel.current_directory;
                if (dir.get_uri_scheme() == "archive") {
                    string? arc_path;
                    string? in_path;
                    if (ArchiveTreeService.split_archive_uri(dir.get_uri(), out arc_path, out in_path)) {
                        string arc_name = Path.get_basename(arc_path);
                        cur_path = (in_path != null && in_path.length > 0) ? @"$arc_name/$in_path" : arc_name;
                    } else {
                        cur_path = dir.get_parse_name();
                    }
                } else {
                    cur_path = dir.get_parse_name();
                }
            }
            if (cur_path != null && cur_path.length > 0) {
                string mode = "detailed";
                if (active_panel != null && active_panel.is_showing_search_results()) {
                    mode = "search results";
                } else if (active_panel != null) {
                    switch (active_panel.view_mode) {
                        case PanelViewMode.BRIEF:
                            mode = "short";
                            break;
                        case PanelViewMode.SUPER:
                            mode = "super detailed";
                            break;
                        case PanelViewMode.GRID:
                            mode = "thumbnails";
                            break;
                        default:
                            mode = "detailed";
                            break;
                    }
                }
                title_label.label = @"[ $cur_path ] — $mode — Vala Commander $ver";
                title_label.tooltip_text = @"[ $cur_path ] — $mode — Vala Commander $ver";
                title = @"[ $cur_path ] — $mode — Vala Commander $ver";
            } else {
                title_label.label = @"Vala Commander $ver";
                title_label.tooltip_text = @"Vala Commander $ver";
                title = @"Vala Commander $ver";
            }
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

        public string? terminal_ssh_agent() {
            return RemoteMount.discover_agent(terminal_child_pid);
        }

        public void show_file_search() {
            if (active_panel == null) {
                return;
            }
            var page = active_panel.get_current_page();
            if (page == null || page.current_directory == null) {
                return;
            }
            bool hidden = page.show_hidden;
            File start = page.current_directory;
            var dialog = SearchDialog.show(this, start, hidden);
            if (dialog == null) {
                return;
            }
            dialog.ready.connect((root, items, summary) => {
                if (active_panel == null) {
                    return;
                }
                var panel = active_panel;
                activate_panel(panel, false);
                panel.open_new_tab(root, "super", hidden, "Search", "name", "asc", true);
                var result_page = panel.get_current_page();
                if (result_page != null) {
                    result_page.present_search_results(root, items, summary);
                }
                activate_panel(panel, true);
            });
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
            update_super_view_layout();
            update_window_title();
            update_function_bar_trash_state();
            if (console_drawer.visible && active_panel != null && active_panel.current_directory != null) {
                string? p = resolve_local_path_for_file(active_panel.current_directory);
                if (p != null) {
                    sync_terminal_directory(p);
                }
            }
            if (focus_list) {
                active_panel.grab_focus_to_list();
            }
        }

        public void update_super_view_layout() {
            if (active_panel == null) return;

            if (active_panel.is_super_view || active_panel.is_grid_view) {
                // If we haven't saved dual paned position yet, remember it
                if (saved_dual_paned_position < 0) {
                    if (paned.position > 0) {
                        saved_dual_paned_position = paned.position;
                    } else {
                        var cfg = ConfigManager.get_instance();
                        saved_dual_paned_position = cfg.paned_position > 0 ? cfg.paned_position : 512;
                    }
                }
                // Maximize active panel, minimize opposite panel
                if (active_panel == left_panel) {
                    left_panel.visible = true;
                    right_panel.visible = false;
                } else {
                    left_panel.visible = false;
                    right_panel.visible = true;
                }
            } else {
                // Active panel is not in full-width view (super detailed or grid)
                left_panel.visible = true;
                right_panel.visible = true;
                if (saved_dual_paned_position > 0) {
                    paned.position = saved_dual_paned_position;
                    saved_dual_paned_position = -1;
                }
            }
        }

        public void trigger_paned_reset_to_half() {
            paned_resetting_half = true;
            reset_paned_to_half();

            // Enforce reset after events settle
            GLib.Timeout.add(50, () => {
                reset_paned_to_half();
                return GLib.Source.REMOVE;
            });
            GLib.Timeout.add(150, () => {
                reset_paned_to_half();
                paned_resetting_half = false;
                return GLib.Source.REMOVE;
            });
        }

        public void reset_paned_to_half() {
            int width = paned.get_width();
            if (width > 0) {
                paned.position = width / 2;
                saved_dual_paned_position = paned.position;
                save_state();
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
                    if (handle_builtin_cd(cmd)) {
                        if (active_panel != null) {
                            active_panel.grab_focus_to_list();
                        }
                        return;
                    }

                    set_console_visible(true);
                    if (vte_terminal != null) {
                        vte_terminal.feed_child((cmd + "\n").data);
                    }
                    return;
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
                        show_command_toast("cd: Not a directory");
                    }
                } else {
                    show_command_toast("cd: No such directory");
                }
                return true;
            }
            return false;
        }

        public void show_command_toast(string message) {
            if (toast_overlay != null) {
                var toast = new Adw.Toast(message);
                toast.timeout = 3;
                toast_overlay.add_toast(toast);
            }
        }

        public void handle_mount_removed(File unmounted_root) {
            check_and_fallback_panel_dir(left_panel, unmounted_root);
            check_and_fallback_panel_dir(right_panel, unmounted_root);

            // Also check console drawer terminal working directory
            string? unmounted_path = unmounted_root.get_path();
            if (unmounted_path != null && terminal_child_pid > 1) {
                try {
                    string shell_cwd = FileUtils.read_link(@"/proc/$terminal_child_pid/cwd");
                    if (shell_cwd == unmounted_path || shell_cwd.has_prefix(unmounted_path + "/")) {
                        string home_path = Environment.get_home_dir();
                        sync_terminal_directory(home_path);
                    }
                } catch (Error e) {
                    // ignore
                }
            }

            save_state();
        }

        private void check_and_fallback_panel_dir(FilePanel panel, File unmounted_root) {
            var home = File.new_for_path(Environment.get_home_dir());
            string? unmounted_path = unmounted_root.get_path();
            string unmounted_uri = unmounted_root.get_uri();
            string unmounted_uri_slash = unmounted_uri.has_suffix("/") ? unmounted_uri : (unmounted_uri + "/");

            for (int i = 0; i < panel.tab_view.n_pages; i++) {
                var page = panel.tab_view.get_nth_page(i);
                if (page != null && page.child is FilePanelPage) {
                    var panel_page = (FilePanelPage) page.child;
                    var cur = panel_page.current_directory;
                    if (cur == null) continue;

                    bool match = cur.equal(unmounted_root) || cur.has_prefix(unmounted_root);
                    if (!match && unmounted_path != null) {
                        string? cur_path = cur.get_path();
                        if (cur_path != null) {
                            if (cur_path == unmounted_path || cur_path.has_prefix(unmounted_path + "/")) {
                                match = true;
                            }
                        }
                    }
                    if (!match) {
                        string cur_uri = cur.get_uri();
                        if (cur_uri == unmounted_uri || cur_uri.has_prefix(unmounted_uri_slash)) {
                            match = true;
                        } else if (unmounted_path != null && cur_uri.has_prefix("archive://")) {
                            string? arc_path;
                            string? in_path;
                            if (ArchiveTreeService.split_archive_uri(cur_uri, out arc_path, out in_path)) {
                                if (arc_path != null && (arc_path == unmounted_path || arc_path.has_prefix(unmounted_path + "/"))) {
                                    match = true;
                                }
                            }
                        }
                    }

                    if (match) {
                        panel_page.load_directory(home);
                    }
                }
            }
        }

        public void toggle_drives_menu() {
            if (drives_button != null) {
                if (drives_button.active) {
                    drives_button.popdown();
                } else {
                    drives_button.popup();
                }
            }
        }

        public void show_drives_menu() {
            if (drives_button != null && !drives_button.active) {
                drives_button.popup();
            }
        }

        public void toggle_operations_menu() {
            int queued_mgr = DriveQueueManager.get_instance().queued_count;
            if (operations_button != null && (operations_button.visible || background_tasks.length > 0 || queued_mgr > 0)) {
                if (!operations_button.visible) {
                    update_operations_button();
                }
                if (operations_button.active) {
                    operations_button.popdown();
                } else {
                    operations_button.popup();
                }
            } else {
                show_command_toast("No background operations running");
            }
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
            safe_present_alert.begin(dialog);
        }

        private async void wait_for_dialogs_to_clear() {
            int attempts = 0;
            while (get_visible_dialog() != null && attempts < 25) {
                Timeout.add(20, wait_for_dialogs_to_clear.callback);
                yield;
                attempts++;
            }
            if (get_visible_dialog() != null) {
                var stuck_dlg = get_visible_dialog();
                if (stuck_dlg is Adw.AlertDialog) {
                    AppLogger.warn("DialogManager", @"Stuck dialog detected ($(stuck_dlg.get_type().name())), forcing close");
                    stuck_dlg.force_close();
                }
            }
        }

        private async void safe_present_dialog(OperationProgressDialog dlg) {
            yield wait_for_dialogs_to_clear();
            if (!dlg.is_finished && !dlg.is_minimized && !dlg.is_queued) {
                dlg.present(this);
            }
        }

        private async void safe_present_alert(Adw.AlertDialog dialog) {
            yield wait_for_dialogs_to_clear();
            dialog.present(this);
        }

        private void attach_progress_dialog(OperationProgressDialog dlg) {
            dlg.minimized.connect(() => {
                on_operation_minimized(dlg);
            });
            dlg.restored.connect(() => {
                on_operation_restored(dlg);
            });
            dlg.progress_updated.connect(() => {
                on_operation_progress_updated(dlg);
            });
            dlg.task_completed.connect(() => {
                on_operation_completed(dlg);
            });
            if (!dlg.is_minimized && !dlg.is_queued) {
                safe_present_dialog.begin(dlg);
            }
        }

        private void register_operation(OperationProgressDialog dlg, GenericArray<string> disks) {
            string? busy_disk = DriveQueueManager.get_instance().get_first_busy_disk(disks);
            if (busy_disk != null) {
                string friendly_name = DeviceDetector.format_device_name(busy_disk);
                dlg.set_queued(friendly_name);
                dlg.minimize();
                on_operation_minimized(dlg);
                show_command_toast(@"Queued: $(dlg.op_title) (waiting for $friendly_name)");
            }
            attach_progress_dialog(dlg);
        }

        private void on_operation_minimized(OperationProgressDialog dlg) {
            bool found = false;
            for (int i = 0; i < background_tasks.length; i++) {
                if (background_tasks[i] == dlg) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                background_tasks.add(dlg);
            }
            operations_popover.add_task(dlg);
            update_operations_button();
        }

        private void on_operation_restored(OperationProgressDialog dlg) {
            for (int i = 0; i < background_tasks.length; i++) {
                if (background_tasks[i] == dlg) {
                    background_tasks.remove_index(i);
                    break;
                }
            }
            operations_popover.remove_task(dlg);
            update_operations_button();
        }

        private void on_operation_completed(OperationProgressDialog dlg) {
            bool was_background = false;
            for (int i = 0; i < background_tasks.length; i++) {
                if (background_tasks[i] == dlg) {
                    background_tasks.remove_index(i);
                    was_background = true;
                    break;
                }
            }
            operations_popover.remove_task(dlg);
            update_operations_button();

            if (was_background || dlg.is_minimized || dlg.is_queued) {
                if (dlg.cancellable.is_cancelled()) {
                    show_command_toast(@"Cancelled: $(dlg.op_title)");
                } else {
                    show_command_toast(@"Completed: $(dlg.op_title)");
                }
            }
        }

        private void on_operation_progress_updated(OperationProgressDialog dlg) {
            update_operations_button();
        }

        private void restore_operation(OperationProgressDialog dlg) {
            operations_popover.popdown();
            dlg.restore(this);
        }

        private void cancel_operation(OperationProgressDialog dlg) {
            dlg.cancellable.cancel();
        }

        private void update_operations_button() {
            int queued_mgr = DriveQueueManager.get_instance().queued_count;
            if (background_tasks.length == 0 && queued_mgr == 0) {
                operations_button.visible = false;
                operations_popover.popdown();
                return;
            }

            operations_button.visible = true;

            int active_count = 0;
            int queued_count = 0;
            int total_pct = 0;
            OperationProgressDialog? first_active = null;

            for (int i = 0; i < background_tasks.length; i++) {
                var t = background_tasks[i];
                if (t.is_queued) {
                    queued_count++;
                } else {
                    active_count++;
                    if (first_active == null) first_active = t;
                    total_pct += (int) (t.current_fraction * 100);
                }
            }

            if (queued_mgr > queued_count) {
                queued_count = queued_mgr;
            }

            if (active_count == 0 && queued_count > 0) {
                operations_label.label = @"Queued ($queued_count)";
                operations_button.tooltip_text = @"$queued_count operation(s) waiting in queue\nClick to view background operations";
            } else if (active_count == 1 && queued_count == 0) {
                var task = first_active;
                int pct = (task != null) ? (int) (task.current_fraction * 100) : 0;
                if (task != null && task.is_synchronizing) {
                    operations_label.label = "Syncing...";
                    operations_button.tooltip_text = @"$(task.op_title): Synchronizing write buffers\nClick to view background operations";
                } else if (pct > 0) {
                    operations_label.label = @"$pct%";
                    operations_button.tooltip_text = (task != null) ? @"$(task.op_title) ($pct%)\nClick to view background operations" : "Background operations";
                } else {
                    operations_label.label = "Working...";
                    operations_button.tooltip_text = (task != null) ? @"$(task.op_title)\nClick to view background operations" : "Background operations";
                }
            } else if (active_count == 1 && queued_count > 0) {
                int pct = (first_active != null) ? (int) (first_active.current_fraction * 100) : 0;
                operations_label.label = @"$pct% ($queued_count queued)";
                string t_title = (first_active != null) ? first_active.op_title : "Active operation";
                operations_button.tooltip_text = @"$t_title ($pct%)\n$queued_count operation(s) waiting in queue\nClick to view background operations";
            } else {
                int avg_pct = (active_count > 0) ? (total_pct / active_count) : 0;
                string q_str = (queued_count > 0) ? @" • $queued_count queued" : "";
                operations_label.label = @"$active_count ops ($avg_pct%)$q_str";
                operations_button.tooltip_text = @"$active_count active ($avg_pct%), $queued_count queued\nClick to view background operations";
            }
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

        private void on_ctrl_u_swap_panels() {
            var left_page = left_panel.get_current_page();
            var right_page = right_panel.get_current_page();
            if (left_page == null || right_page == null) return;
            if (left_page.current_directory == null || right_page.current_directory == null) return;

            File dir_left = left_page.current_directory;
            File dir_right = right_page.current_directory;

            var sel_left = left_page.get_selected_item();
            string? sel_left_name = (sel_left != null && !sel_left.is_parent_dir) ? sel_left.name : null;

            var sel_right = right_page.get_selected_item();
            string? sel_right_name = (sel_right != null && !sel_right.is_parent_dir) ? sel_right.name : null;

            string? title_left = left_page.custom_title;
            string? title_right = right_page.custom_title;

            PanelViewMode vmode_left = left_page.view_mode;
            PanelViewMode vmode_right = right_page.view_mode;

            string sort_col_left = left_page.sort_column_id;
            string sort_ord_left = left_page.sort_order_str;
            string sort_col_right = right_page.sort_column_id;
            string sort_ord_right = right_page.sort_order_str;

            bool pin_left = left_page.is_pinned;
            bool pin_right = right_page.is_pinned;

            // Apply right state to left panel's active tab
            left_page.custom_title = title_right;
            left_page.is_pinned = pin_right;
            if (left_page.view_mode != vmode_right) {
                left_page.switch_view_mode(vmode_right);
            }
            left_page.apply_sort(sort_col_right, sort_ord_right);
            left_page.load_directory(dir_right, sel_right_name);
            left_panel.update_tab_title(left_page);

            // Apply left state to right panel's active tab
            right_page.custom_title = title_left;
            right_page.is_pinned = pin_left;
            if (right_page.view_mode != vmode_left) {
                right_page.switch_view_mode(vmode_left);
            }
            right_page.apply_sort(sort_col_left, sort_ord_left);
            right_page.load_directory(dir_left, sel_left_name);
            right_panel.update_tab_title(right_page);

            left_panel.tabs_state_changed(left_panel);
            right_panel.tabs_state_changed(right_panel);

            update_window_title();
            if (console_drawer.visible && active_panel != null && active_panel.current_directory != null) {
                string? path = resolve_local_path_for_file(active_panel.current_directory);
                if (path != null) {
                    sync_terminal_directory(path);
                }
            }
            if (active_panel != null) {
                active_panel.grab_focus_to_list();
            }
        }

        private void prompt_select_by_mask() {
            if (active_panel == null) return;

            var dialog = new Adw.AlertDialog("Select by Mask", "Enter filename mask (e.g. *.lst, *abc*):");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("select", "Select");
            dialog.set_default_response("select");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("select", Adw.ResponseAppearance.SUGGESTED);

            var config = ConfigManager.get_instance();

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_start = 12;
            box.margin_end = 12;
            box.margin_top = 8;
            box.margin_bottom = 8;

            var entry = new Gtk.Entry();
            entry.text = (config.select_mask != null && config.select_mask.length > 0) ? config.select_mask : "*";
            entry.placeholder_text = "*.lst, *abc*";

            var check_dirs = new Gtk.CheckButton.with_label("Apply to folders");
            check_dirs.active = config.select_mask_include_dirs;

            box.append(entry);
            box.append(check_dirs);
            dialog.set_extra_child(box);

            entry.activate.connect(() => {
                string pattern = entry.text.strip();
                bool inc_dirs = check_dirs.active;
                dialog.force_close();
                if (pattern.length > 0 && active_panel != null) {
                    config.select_mask = pattern;
                    config.select_mask_include_dirs = inc_dirs;
                    config.save();

                    active_panel.select_by_mask(pattern, inc_dirs);
                    active_panel.grab_focus_to_list();
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "select") {
                    string pattern = entry.text.strip();
                    if (pattern.length > 0 && active_panel != null) {
                        config.select_mask = pattern;
                        config.select_mask_include_dirs = check_dirs.active;
                        config.save();

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
            if (active_panel.is_archive_location) {
                show_error_dialog("Create Folder", "Cannot create folders inside archives.");
                return;
            }
            if (active_panel.is_trash_location) {
                show_error_dialog("Create Folder", "Cannot create folders inside Trash.");
                return;
            }
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
            if (active_panel.is_archive_location) {
                show_error_dialog("Delete Error", "Deleting files from archives is not supported.");
                return;
            }

            var target_panel = active_panel;
            string? select_above_name = target_panel.get_item_above_selection_or_first_tag();

            var tagged_items = target_panel.get_tagged_items();
            if (tagged_items.length > 0) {
                if (target_panel.is_trash_location) {
                    var dialog = new Adw.AlertDialog(
                        "Permanently Delete",
                        @"Permanently delete $(tagged_items.length) selected items from Trash? This action cannot be undone."
                    );
                    dialog.add_response("cancel", "Cancel");
                    dialog.add_response("delete", "Delete Permanently");
                    dialog.set_default_response("cancel");
                    dialog.set_close_response("cancel");
                    dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);

                    dialog.choose.begin(this, null, (obj, res) => {
                        string resp = dialog.choose.end(res);
                        if (resp == "delete") {
                            do_delete_multiple_items.begin(target_panel, tagged_items, true, select_above_name);
                        } else {
                            target_panel.grab_focus_to_list();
                        }
                    });
                    return;
                }

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
                        do_delete_multiple_items.begin(target_panel, tagged_items, perm_check.active, select_above_name);
                    } else {
                        target_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            var item = target_panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Delete", "Cannot delete parent directory '..'.");
                return;
            }

            string item_name = item.display_name;

            if (target_panel.is_trash_location) {
                var dialog = new Adw.AlertDialog(
                    "Permanently Delete",
                    @"Permanently delete '$item_name' from Trash? This action cannot be undone."
                );
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("delete", "Delete Permanently");
                dialog.set_default_response("cancel");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "delete") {
                        do_delete_item.begin(target_panel, item.file, true, select_above_name);
                    } else {
                        target_panel.grab_focus_to_list();
                    }
                });
                return;
            }

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
                    do_delete_item.begin(target_panel, item.file, perm_check.active, select_above_name);
                } else {
                    target_panel.grab_focus_to_list();
                }
            });
        }

        private async void do_delete_item(FilePanel panel, File target, bool permanent, string? select_above_name) {
            string op_name = permanent ? "Permanent delete" : "Trash";
            AppLogger.info("FileOperation", @"$op_name requested: '$(target.get_path() ?? target.get_uri())'");
            try {
                if (permanent) {
                    yield FileOperationService.delete_recursive(target);
                } else {
                    yield FileOperationService.trash_file(target);
                }
                AppLogger.info("FileOperation", @"$op_name completed: '$(target.get_path() ?? target.get_uri())'");
                if (panel.current_directory != null) {
                    panel.load_directory(panel.current_directory, select_above_name);
                } else {
                    panel.refresh();
                }
                activate_panel(panel, true);
                var opp = (panel == left_panel) ? right_panel : left_panel;
                if (opp.current_directory != null && panel.current_directory != null && opp.current_directory.equal(panel.current_directory)) {
                    opp.refresh();
                }
                panel.grab_focus_to_list();
            } catch (Error e) {
                AppLogger.error("FileOperation", @"$op_name failed: '$(target.get_path() ?? target.get_uri())'", e.message);
                show_error_dialog("Delete Error", FileOperationService.format_error(e, permanent ? "delete" : "trash"));
                panel.grab_focus_to_list();
            }
        }

        private async void do_delete_multiple_items(FilePanel panel, GenericArray<FileItem> items, bool permanent, string? select_above_name) {
            var cancellable = new Cancellable();
            string op_title = permanent ? @"Permanently deleting $(items.length) items" : @"Moving $(items.length) items to Trash";
            var dlg = new OperationProgressDialog(op_title, cancellable);
            attach_progress_dialog(dlg);

            string op_name = permanent ? "Multi-delete" : "Multi-trash";
            AppLogger.info("FileOperation", @"$op_name requested: $(items.length) items");
            try {
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    dlg.update_progress(it.display_name, i + 1, items.length);
                    if (permanent) {
                        yield FileOperationService.delete_recursive(it.file, cancellable);
                    } else {
                        yield FileOperationService.trash_file(it.file, cancellable);
                    }
                }
                dlg.finish();
                if (!cancellable.is_cancelled()) {
                    AppLogger.info("FileOperation", @"$op_name completed: $(items.length) items");
                    panel.clear_tags();
                }
                if (panel.current_directory != null) {
                    panel.load_directory(panel.current_directory, select_above_name);
                } else {
                    panel.refresh();
                }
                activate_panel(panel, true);
                var opp = (panel == left_panel) ? right_panel : left_panel;
                if (opp.current_directory != null && panel.current_directory != null && opp.current_directory.equal(panel.current_directory)) {
                    opp.refresh();
                }
                panel.grab_focus_to_list();
            } catch (Error e) {
                dlg.finish();
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("FileOperation", @"$op_name cancelled: $(items.length) items");
                } else {
                    AppLogger.error("FileOperation", @"$op_name failed: $(items.length) items", e.message);
                    show_error_dialog("Delete Error", FileOperationService.format_error(e, permanent ? "delete" : "trash"));
                }
                if (panel.current_directory != null) {
                    panel.load_directory(panel.current_directory, select_above_name);
                } else {
                    panel.refresh();
                }
                activate_panel(panel, true);
                var opp = (panel == left_panel) ? right_panel : left_panel;
                if (opp.current_directory != null && panel.current_directory != null && opp.current_directory.equal(panel.current_directory)) {
                    opp.refresh();
                }
                panel.grab_focus_to_list();
            }
        }

        private const int64 LARGE_FILE_THRESHOLD_BYTES = 30 * 1024 * 1024; // 30 MB

        private void on_f3_view() {
            if (active_panel == null) return;
            var target_panel = active_panel;
            var item = target_panel.get_selected_item();
            if (item == null) return;

            if (item.is_parent_dir) {
                show_error_dialog("File Viewer", "Cannot view the parent directory.");
                return;
            }
            if (item.is_dir) {
                show_error_dialog("File Viewer", "Cannot view a directory. Please select a file.");
                return;
            }

            var config = ConfigManager.get_instance();
            string cmd = (config.viewer_command != null && config.viewer_command.length > 0)
                ? config.viewer_command
                : ConfigManager.detect_default_editor();

            string? path = item.file.get_path();
            if (path == null && item.file.get_uri_scheme() == "archive") {
                string? arc_path;
                string? in_path;
                if (ArchiveTreeService.split_archive_uri(item.file.get_uri(), out arc_path, out in_path) && arc_path != null && in_path != null) {
                    var temp_file = ArchiveTreeService.get_temp_extracted_file(arc_path, in_path);
                    extract_archive_file_and_launch.begin(arc_path, in_path, temp_file, cmd, "File Viewer", target_panel, item.name);
                    return;
                }
            }
            if (path == null) {
                show_error_dialog("File Viewer", "Selected file does not have a local path.");
                return;
            }

            if (item.size > LARGE_FILE_THRESHOLD_BYTES) {
                var dialog = new Adw.AlertDialog(
                    "Warning: large file",
                    @"The file '$(item.display_name)' is very large ($(GLib.format_size(item.size))).\nOpening it may take significant time or freeze the editor.\n\nDo you want to open it anyway?"
                );
                dialog.set_prefer_wide_layout(true);
                dialog.set_content_width(520);
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("open", "Open Anyway");
                dialog.set_default_response("cancel");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("open", Adw.ResponseAppearance.DESTRUCTIVE);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "open") {
                        launch_external_file_tool(cmd, path, "File Viewer", target_panel, item.name);
                    } else {
                        target_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            launch_external_file_tool(cmd, path, "File Viewer", target_panel, item.name);
        }

        private async void extract_archive_file_and_launch(string arc_path, string in_path, File temp_file, string cmd, string title, FilePanel target_panel, string item_name) {
            bool is_retry = false;
            while (true) {
                try {
                    yield ArchiveTreeService.extract_single_file_to(arc_path, in_path, temp_file, null);
                    launch_external_file_tool(cmd, temp_file.get_path(), title, target_panel, item_name);
                    break;
                } catch (ArchivePasswordError e) {
                    is_retry = (e is ArchivePasswordError.INVALID);
                    string? pwd = yield ArchivePasswordDialog.prompt_async(this, Path.get_basename(arc_path), is_retry);
                    if (pwd == null) {
                        break;
                    }
                    ArchiveTreeService.set_cached_password(arc_path, pwd);
                } catch (Error e) {
                    show_error_dialog(title, @"Cannot extract $(Path.get_basename(in_path)): $(e.message)");
                    break;
                }
            }
        }

        public void open_application_log() {
            string log_path = AppLogger.get_log_file_path();
            if (!FileUtils.test(log_path, FileTest.EXISTS)) {
                AppLogger.info("System", "Application log initialized.");
            }

            var config = ConfigManager.get_instance();
            string cmd = (config.editor_command != null && config.editor_command.length > 0)
                ? config.editor_command
                : ConfigManager.detect_default_editor();

            launch_external_file_tool(cmd, log_path, "Application Log", active_panel, null);
        }

        private void on_f4_edit() {
            if (active_panel == null) return;
            var target_panel = active_panel;
            var item = target_panel.get_selected_item();
            if (item == null) return;

            if (item.is_parent_dir) {
                show_error_dialog("File Editor", "Cannot edit the parent directory.");
                return;
            }
            if (item.is_dir) {
                show_error_dialog("File Editor", "Cannot edit a directory. Please select a file.");
                return;
            }

            var config = ConfigManager.get_instance();
            string cmd = (config.editor_command != null && config.editor_command.length > 0)
                ? config.editor_command
                : ConfigManager.detect_default_editor();

            string? path = item.file.get_path();
            if (path == null && item.file.get_uri_scheme() == "archive") {
                string? arc_path;
                string? in_path;
                if (ArchiveTreeService.split_archive_uri(item.file.get_uri(), out arc_path, out in_path) && arc_path != null && in_path != null) {
                    if (item.size > LARGE_FILE_THRESHOLD_BYTES) {
                        var dialog = new Adw.AlertDialog(
                            "Warning: large file",
                            @"The file '$(item.display_name)' is very large ($(GLib.format_size(item.size))).\nOpening it may take significant time or freeze the editor.\n\nDo you want to open it anyway?"
                        );
                        dialog.set_prefer_wide_layout(true);
                        dialog.set_content_width(520);
                        dialog.add_response("cancel", "Cancel");
                        dialog.add_response("open", "Open Anyway");
                        dialog.set_default_response("cancel");
                        dialog.set_close_response("cancel");
                        dialog.set_response_appearance("open", Adw.ResponseAppearance.DESTRUCTIVE);

                        dialog.choose.begin(this, null, (obj, res) => {
                            string resp = dialog.choose.end(res);
                            if (resp == "open") {
                                var temp_file = ArchiveTreeService.get_temp_extracted_file(arc_path, in_path);
                                extract_archive_file_and_edit.begin(arc_path, in_path, temp_file, cmd, target_panel, item.name);
                            } else {
                                target_panel.grab_focus_to_list();
                            }
                        });
                        return;
                    }

                    var temp_file = ArchiveTreeService.get_temp_extracted_file(arc_path, in_path);
                    extract_archive_file_and_edit.begin(arc_path, in_path, temp_file, cmd, target_panel, item.name);
                    return;
                }
            }
            if (path == null) {
                show_error_dialog("File Editor", "Selected file does not have a local path.");
                return;
            }

            if (item.size > LARGE_FILE_THRESHOLD_BYTES) {
                var dialog = new Adw.AlertDialog(
                    "Warning: large file",
                    @"The file '$(item.display_name)' is very large ($(GLib.format_size(item.size))).\nOpening it may take significant time or freeze the editor.\n\nDo you want to open it anyway?"
                );
                dialog.set_prefer_wide_layout(true);
                dialog.set_content_width(520);
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("open", "Open Anyway");
                dialog.set_default_response("cancel");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("open", Adw.ResponseAppearance.DESTRUCTIVE);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "open") {
                        launch_external_file_tool(cmd, path, "File Editor", target_panel, item.name);
                    } else {
                        target_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            launch_external_file_tool(cmd, path, "File Editor", target_panel, item.name);
        }

        private async void extract_archive_file_and_edit(string arc_path, string in_path, File temp_file, string cmd, FilePanel target_panel, string item_name) {
            bool is_retry = false;
            while (true) {
                try {
                    yield ArchiveTreeService.extract_single_file_to(arc_path, in_path, temp_file, null);
                    break;
                } catch (ArchivePasswordError e) {
                    is_retry = (e is ArchivePasswordError.INVALID);
                    string? pwd = yield ArchivePasswordDialog.prompt_async(this, Path.get_basename(arc_path), is_retry);
                    if (pwd == null) {
                        return;
                    }
                    ArchiveTreeService.set_cached_password(arc_path, pwd);
                } catch (Error e) {
                    show_error_dialog("File Editor", @"Cannot extract $(Path.get_basename(in_path)): $(e.message)");
                    return;
                }
            }

            int64 initial_mtime = 0;
            int64 initial_size = 0;
            try {
                var info = yield temp_file.query_info_async(FileAttribute.TIME_MODIFIED + "," + FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                var dt = info.get_modification_date_time();
                initial_mtime = (dt != null) ? dt.to_unix() : 0;
                initial_size = info.get_size();
            } catch (Error e) {}

            bool ran = yield launch_external_file_tool_async(cmd, temp_file.get_path(), "File Editor", target_panel, item_name);
            if (!ran) return;

            int64 post_mtime = 0;
            int64 post_size = 0;
            try {
                var info = yield temp_file.query_info_async(FileAttribute.TIME_MODIFIED + "," + FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                var dt = info.get_modification_date_time();
                post_mtime = (dt != null) ? dt.to_unix() : 0;
                post_size = info.get_size();
            } catch (Error e) {}

            bool modified = (post_mtime != initial_mtime) || (post_size != initial_size);
            if (modified) {
                prompt_archive_member_update(arc_path, in_path, temp_file, target_panel);
            }
        }

        private void prompt_archive_member_update(string arc_path, string in_path, File temp_file, FilePanel target_panel) {
            string member_name = Path.get_basename(in_path);
            string arc_name = Path.get_basename(arc_path);
            var dialog = new Adw.AlertDialog(
                "Update Archive Member?",
                @"The file '$member_name' has been modified.\nDo you want to update it in '$arc_name'?"
            );
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("update", "Update");
            dialog.set_default_response("update");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("update", Adw.ResponseAppearance.SUGGESTED);

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "update") {
                    do_update_archive_member.begin(arc_path, in_path, temp_file, target_panel);
                } else {
                    target_panel.grab_focus_to_list();
                }
            });
        }

        private async void do_update_archive_member(string arc_path, string in_path, File temp_file, FilePanel target_panel) {
            string member_name = Path.get_basename(in_path);
            string arc_name = Path.get_basename(arc_path);
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Updating member '$member_name'", cancellable);

            File arc_file = File.new_for_path(arc_path);
            var disks = DriveQueueManager.get_required_disks(temp_file, arc_file);
            register_operation(dlg, disks);

            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);
                yield ArchiveOperationService.update_archive_member(arc_path, in_path, temp_file, cancellable);
                ArchiveTreeService.clear_cache(arc_path);
                show_command_toast(@"Updated '$member_name' in $arc_name");
                target_panel.refresh();
                var opp = (target_panel == left_panel) ? right_panel : left_panel;
                if (opp.is_archive_location && opp.current_directory != null && opp.current_directory.get_uri().has_prefix("archive://" + Uri.escape_string(arc_path))) {
                    opp.refresh();
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_command_toast("Archive update cancelled");
                } else {
                    show_error_dialog("Update Archive", @"Failed to update '$member_name': $(e.message)");
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                activate_panel(target_panel, true);
            }
        }

        private void launch_external_file_tool(string command_template, string file_path, string tool_title, FilePanel target_panel, string? selected_name) {
            launch_external_file_tool_async.begin(command_template, file_path, tool_title, target_panel, selected_name);
        }

        private async bool launch_external_file_tool_async(string command_template, string file_path, string tool_title, FilePanel target_panel, string? selected_name) {
            string cmd_str = command_template.strip();
            if (cmd_str.length == 0) {
                cmd_str = ConfigManager.detect_default_editor();
            }

            try {
                string[] parsed_argv;
                Shell.parse_argv(cmd_str, out parsed_argv);

                if (parsed_argv.length == 0) {
                    show_error_dialog(tool_title, @"Invalid command: '$command_template'");
                    return false;
                }

                var final_argv = new GenericArray<string>();
                bool placeholder_found = false;

                foreach (var arg in parsed_argv) {
                    if (arg.contains("%f")) {
                        final_argv.add(arg.replace("%f", file_path));
                        placeholder_found = true;
                    } else {
                        final_argv.add(arg);
                    }
                }

                if (!placeholder_found) {
                    final_argv.add(file_path);
                }

                string base_bin = Path.get_basename(parsed_argv[0]);
                string[] spawn_args;

                if (is_terminal_command(base_bin)) {
                    string? term = find_terminal_emulator();
                    if (term == null) {
                        show_error_dialog(tool_title,
                            @"No terminal emulator found to run '$base_bin'. Please install gnome-terminal or ptyxis, or configure a graphical editor like gnome-text-editor or gvim.");
                        return false;
                    }

                    var term_argv = new GenericArray<string>();
                    term_argv.add(term);

                    string term_base = Path.get_basename(term);
                    if (term_base == "gnome-terminal" || term_base == "ptyxis") {
                        term_argv.add("--wait");
                        term_argv.add("--");
                    } else if (term_base == "kitty" || term_base == "alacritty") {
                        term_argv.add("--");
                    } else if (term_base == "konsole") {
                        term_argv.add("--nofork");
                        term_argv.add("-e");
                    } else {
                        term_argv.add("-e");
                    }

                    for (int i = 0; i < final_argv.length; i++) {
                        term_argv.add(final_argv[i]);
                    }

                    spawn_args = new string[term_argv.length];
                    for (int i = 0; i < term_argv.length; i++) {
                        spawn_args[i] = term_argv[i];
                    }
                } else {
                    spawn_args = new string[final_argv.length];
                    for (int i = 0; i < final_argv.length; i++) {
                        spawn_args[i] = final_argv[i];
                    }
                }

                return yield spawn_tool_and_watch(spawn_args, file_path, tool_title, target_panel, selected_name);
            } catch (Error e) {
                show_error_dialog(tool_title, @"Failed to launch '$command_template': $(e.message)");
                return false;
            }
        }

        private async bool spawn_tool_and_watch(string[] argv, string file_path, string tool_title, FilePanel target_panel, string? selected_name) {
            try {
                var launcher = new SubprocessLauncher(SubprocessFlags.NONE);
                string? cwd = Path.get_dirname(file_path);
                if (cwd != null) {
                    launcher.set_cwd(cwd);
                }
                var proc = launcher.spawnv(argv);

                // Ensure the originating panel retains focus immediately upon launching
                activate_panel(target_panel, true);

                yield proc.wait_async(null);

                // A viewer or editor must not replace an open search-results tab.
                if (!target_panel.is_showing_search_results()) {
                    if (target_panel.current_directory != null) {
                        target_panel.load_directory(target_panel.current_directory, selected_name);
                    } else {
                        target_panel.refresh();
                    }
                }

                // If opposite panel has the same directory, refresh it as well
                var opp = (target_panel == left_panel) ? right_panel : left_panel;
                if (opp.current_directory != null && cwd != null) {
                    if (opp.current_directory.get_path() == cwd) {
                        opp.refresh();
                    }
                }

                // Re-assert focus and active state on target_panel
                activate_panel(target_panel, true);
                return true;
            } catch (Error e) {
                show_error_dialog(tool_title, @"Error executing tool: $(e.message)");
                activate_panel(target_panel, true);
                return false;
            }
        }

        private static bool is_terminal_command(string binary_name) {
            string[] term_apps = {
                "vim", "vi", "nvim", "nano", "less", "more", "view",
                "mcview", "mcedit", "joe", "micro", "emacs-nw"
            };
            foreach (var app in term_apps) {
                if (binary_name == app) {
                    return true;
                }
            }
            return false;
        }

        private static string? find_terminal_emulator() {
            string[] terminals = {
                "ptyxis", "gnome-terminal", "x-terminal-emulator",
                "kitty", "alacritty", "konsole", "xfce4-terminal", "xterm"
            };
            foreach (var term in terminals) {
                if (Environment.find_program_in_path(term) != null) {
                    return term;
                }
            }
            return null;
        }

        private void on_pack_archive() {
            if (active_panel == null) return;

            if (active_panel.is_archive_location) {
                show_error_dialog("Archive Error", "Cannot create archives from items inside another archive.");
                return;
            }

            if (active_panel.is_trash_location) {
                show_error_dialog("Archive Error", "Cannot create archives from Trash items. Please restore them first.");
                return;
            }

            var tagged_items = active_panel.get_tagged_items();
            var items_to_pack = new GenericArray<FileItem>();

            if (tagged_items.length > 0) {
                for (uint i = 0; i < tagged_items.length; i++) {
                    items_to_pack.add(tagged_items.get(i));
                }
            } else {
                var sel = active_panel.get_selected_item();
                if (sel == null || sel.is_parent_dir) {
                    show_error_dialog("Pack Archive", "Please select or tag one or more files or folders to archive.");
                    return;
                }
                items_to_pack.add(sel);
            }

            var opp = get_opposite_panel();
            ArchivePackDialog.show(this, active_panel, opp, items_to_pack, (request) => {
                on_archive_pack_confirmed(request);
            });
        }

        private void on_archive_pack_confirmed(ArchivePackRequest request) {
            do_pack_archive.begin(request);
        }

        private async void do_pack_archive(ArchivePackRequest request) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Archiving $(request.destination_archive.get_basename())", cancellable);

            // Compute required disks for DriveQueueManager
            var parent = request.destination_archive.get_parent();
            File dest_ref = (parent != null) ? parent : request.destination_archive;
            var disks = DriveQueueManager.get_required_disks_multi(request.source_items, dest_ref);
            register_operation(dlg, disks);

            AppLogger.info("Archive", @"Pack started: $(request.destination_archive.get_path()) [$(request.format.id), level=$(request.compression_level), items=$(request.source_items.length)]");

            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

                yield ArchiveOperationService.pack_archive(request, dlg, cancellable);

                AppLogger.info("Archive", @"Pack completed successfully: $(request.destination_archive.get_path())");
                show_command_toast(@"Archive created: $(request.destination_archive.get_basename())");

                // Clear tags in active panel
                if (active_panel != null) {
                    active_panel.clear_tags();
                }

                // Refresh panels and select new archive file
                string archive_name = request.destination_archive.get_basename();
                if (parent != null) {
                    if (left_panel.current_directory != null && left_panel.current_directory.equal(parent)) {
                        left_panel.load_directory(parent, archive_name);
                    } else {
                        left_panel.refresh();
                    }

                    if (right_panel.current_directory != null && right_panel.current_directory.equal(parent)) {
                        right_panel.load_directory(parent, archive_name);
                    } else {
                        right_panel.refresh();
                    }
                } else {
                    left_panel.refresh();
                    right_panel.refresh();
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("Archive", @"Pack cancelled: $(request.destination_archive.get_path())");
                    show_command_toast("Archive creation cancelled");
                } else {
                    AppLogger.error("Archive", @"Pack failed: $(request.destination_archive.get_path())", e.message);
                    show_error_dialog("Archive Error", @"Failed to create archive:\n$(e.message)");
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private void on_f5_copy() {
            if (active_panel == null) return;

            if (active_panel.is_archive_location) {
                on_f5_archive_extract();
                return;
            }

            if (active_panel.is_trash_location) {
                show_error_dialog("Copy Error", "Cannot copy files from Trash. Please restore them first.");
                return;
            }

            var tagged_items = active_panel.get_tagged_items();
            var opp = get_opposite_panel();
            File? dest_dir = opp.current_directory;

            if (dest_dir != null && dest_dir.get_uri_scheme() == "archive") {
                show_error_dialog("Copy Error", "Copying files directly into an archive is not supported.");
                return;
            }

            if (dest_dir != null && dest_dir.get_uri_scheme() == "trash") {
                show_error_dialog("Copy Error", "Cannot copy items into Trash. Use Delete (F8) to move items to Trash.");
                return;
            }

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

            if (!item.is_dir && ArchiverRegistry.get_instance().is_archive_filename(item.name) &&
                dest_dir != null && dest_dir.get_uri_scheme() != "archive" && dest_dir.get_uri_scheme() != "trash") {
                prompt_archive_outside_actions(item, dest_dir, opp);
                return;
            }

            prompt_single_file_copy(item, dest_dir);
        }

        private void prompt_single_file_copy(FileItem item, File? dest_dir) {
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

            bool action_executed = false;

            entry.activate.connect(() => {
                if (action_executed) return;
                action_executed = true;
                string dest_input = entry.text.strip();
                dialog.force_close();
                if (dest_input.length > 0) {
                    prompt_execute_copy.begin(item, dest_input);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (action_executed) return;
                if (resp == "copy") {
                    action_executed = true;
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

        public static string strip_archive_extension(string filename) {
            string lower = filename.down();
            string[] multi_exts = {
                ".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2",
                ".tgz", ".txz", ".tzst", ".tbz2",
                ".tar", ".zip", ".7z", ".rar", ".deb", ".rpm",
                ".iso", ".cpio", ".ar", ".cab", ".jar", ".war"
            };
            foreach (var ext in multi_exts) {
                if (lower.has_suffix(ext)) {
                    return filename.substring(0, filename.length - ext.length);
                }
            }
            int dot = filename.last_index_of_char('.');
            if (dot > 0) {
                return filename.substring(0, dot);
            }
            return filename;
        }

        private void prompt_archive_outside_actions(FileItem item, File dest_dir, FilePanel opp_panel) {
            string stem = strip_archive_extension(item.name);
            var dialog = new Adw.AlertDialog("Archive Actions", @"What would you like to do with '$(item.name)'?");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("copy", "Copy File");
            dialog.add_response("extract_subfolder", @"Extract to '$stem/'");
            dialog.add_response("extract_here", "Extract to Opposite Pane");
            dialog.set_default_response("extract_subfolder");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("extract_subfolder", Adw.ResponseAppearance.SUGGESTED);

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "copy") {
                    prompt_single_file_copy(item, dest_dir);
                } else if (resp == "extract_subfolder") {
                    File target_subfolder = dest_dir.get_child(stem);
                    do_extract_full_archive.begin(item.file, target_subfolder, opp_panel);
                } else if (resp == "extract_here") {
                    do_extract_full_archive.begin(item.file, dest_dir, opp_panel);
                } else {
                    if (active_panel != null) active_panel.grab_focus_to_list();
                }
            });
        }

        private void on_f5_archive_extract() {
            var opp = get_opposite_panel();
            File? dest_dir = opp.current_directory;
            if (dest_dir == null) {
                show_error_dialog("Extract Error", "Opposite panel has no directory open.");
                return;
            }
            if (dest_dir.get_uri_scheme() == "archive") {
                show_error_dialog("Extract Error", "Extracting directly into another archive is not supported.");
                return;
            }
            if (dest_dir.get_uri_scheme() == "trash") {
                show_error_dialog("Extract Error", "Cannot extract files into Trash.");
                return;
            }

            var tagged_items = active_panel.get_tagged_items();
            var items_to_extract = new GenericArray<FileItem>();
            if (tagged_items.length > 0) {
                for (uint i = 0; i < tagged_items.length; i++) {
                    items_to_extract.add(tagged_items.get(i));
                }
            } else {
                var sel = active_panel.get_selected_item();
                if (sel == null || sel.is_parent_dir) {
                    show_error_dialog("Extract", "Please select a file or folder to extract.");
                    return;
                }
                items_to_extract.add(sel);
            }

            string? arc_path = null;
            string? in_path = null;
            if (active_panel.current_directory != null) {
                ArchiveTreeService.split_archive_uri(active_panel.current_directory.get_uri(), out arc_path, out in_path);
            }
            if (arc_path == null && items_to_extract.length > 0) {
                ArchiveTreeService.split_archive_uri(items_to_extract.get(0).file.get_uri(), out arc_path, out in_path);
            }
            if (arc_path == null) {
                show_error_dialog("Extract Error", "Cannot determine archive location.");
                return;
            }

            string default_dest_path = dest_dir.get_path();
            if (default_dest_path == null) default_dest_path = dest_dir.get_parse_name();

            string prompt_msg = (items_to_extract.length > 1)
                ? @"Extract $(items_to_extract.length) items to:"
                : @"Extract '$(items_to_extract.get(0).display_name)' to:";

            var dialog = new Adw.AlertDialog("Extract from Archive", prompt_msg);
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("extract", "Extract");
            dialog.set_default_response("extract");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("extract", Adw.ResponseAppearance.SUGGESTED);

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
                    do_extract_vfs_items.begin(arc_path, items_to_extract, File.new_for_commandline_arg(dest_input), opp);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "extract") {
                    string dest_input = entry.text.strip();
                    if (dest_input.length > 0) {
                        do_extract_vfs_items.begin(arc_path, items_to_extract, File.new_for_commandline_arg(dest_input), opp);
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

        private async void do_extract_vfs_items(string arc_path, GenericArray<FileItem> items, File dest_dir, FilePanel opp_panel) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Extracting $(items.length) item(s) from $(Path.get_basename(arc_path))", cancellable);

            File arc_file = File.new_for_path(arc_path);
            var disks = DriveQueueManager.get_required_disks(arc_file, dest_dir);
            register_operation(dlg, disks);

            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);
                while (true) {
                    try {
                        yield ArchiveOperationService.extract_vfs_items(arc_path, items, dest_dir, dlg, cancellable);
                        break;
                    } catch (ArchivePasswordError e) {
                        bool is_retry = (e is ArchivePasswordError.INVALID);
                        string? pwd = yield ArchivePasswordDialog.prompt_async(this, Path.get_basename(arc_path), is_retry);
                        if (pwd == null) {
                            cancellable.cancel();
                            break;
                        }
                        ArchiveTreeService.set_cached_password(arc_path, pwd);
                    }
                }
                if (!cancellable.is_cancelled()) {
                    show_command_toast(@"Extracted $(items.length) item(s) to $(dest_dir.get_basename())");
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_command_toast("Archive extraction cancelled");
                } else {
                    show_error_dialog("Extraction Error", @"Failed to extract from archive: $(e.message)");
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                opp_panel.refresh();
                if (active_panel != null) {
                    active_panel.grab_focus_to_list();
                }
            }
        }

        private async void do_extract_full_archive(File archive_file, File dest_dir, FilePanel opp_panel) {
            string? arc_path = archive_file.get_path();
            if (arc_path == null) {
                show_error_dialog("Extract Error", "Archive must be on local filesystem.");
                return;
            }

            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Extracting $(archive_file.get_basename())", cancellable);

            var disks = DriveQueueManager.get_required_disks(archive_file, dest_dir);
            register_operation(dlg, disks);

            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);
                while (true) {
                    try {
                        yield ArchiveOperationService.extract_full_archive(archive_file, dest_dir, dlg, cancellable);
                        break;
                    } catch (ArchivePasswordError e) {
                        bool is_retry = (e is ArchivePasswordError.INVALID);
                        string? pwd = yield ArchivePasswordDialog.prompt_async(this, Path.get_basename(arc_path), is_retry);
                        if (pwd == null) {
                            cancellable.cancel();
                            break;
                        }
                        ArchiveTreeService.set_cached_password(arc_path, pwd);
                    }
                }
                if (!cancellable.is_cancelled()) {
                    show_command_toast(@"Extracted '$(archive_file.get_basename())' to $(dest_dir.get_basename())");
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_command_toast("Archive extraction cancelled");
                } else {
                    show_error_dialog("Extraction Error", @"Failed to extract archive: $(e.message)");
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                opp_panel.refresh();
                if (active_panel != null) {
                    active_panel.grab_focus_to_list();
                }
            }
        }

        private async void prompt_execute_copy(FileItem item, string dest_input) {
            File? dest_target = yield resolve_dest_file_async(item, dest_input, "Copy");
            if (dest_target == null) return;

            if (dest_target.equal(item.file)) {
                show_error_dialog("Copy Error", "Source and destination cannot be the same.");
                return;
            }

            bool dest_exists = yield FileOperationService.file_exists_async(dest_target);
            if (dest_exists) {
                yield wait_for_dialogs_to_clear();
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
            var disks = DriveQueueManager.get_required_disks(source, dest);
            register_operation(dlg, disks);

            var tracker = new CopyProgressTracker();
            AppLogger.info("FileOperation", @"Copy requested: '$(source.get_basename())' -> '$(dest.get_path() ?? dest.get_uri())'");
            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

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
                AppLogger.info("FileOperation", @"Copy completed successfully: '$(source.get_basename())'");
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("FileOperation", @"Copy cancelled: '$(source.get_basename())'");
                } else {
                    AppLogger.error("FileOperation", @"Copy failed: '$(source.get_basename())'", e.message);
                    show_error_dialog("Copy Error", FileOperationService.format_error(e, "copy"));
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private async void do_copy_multiple_items(GenericArray<FileItem> items, File dest_dir) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Copying $(items.length) items", cancellable);
            var disks = DriveQueueManager.get_required_disks_multi(items, dest_dir);
            register_operation(dlg, disks);
            var tracker = new CopyProgressTracker();
            AppLogger.info("FileOperation", @"Multi-copy requested: $(items.length) items -> '$(dest_dir.get_path() ?? dest_dir.get_uri())'");
            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

                dlg.update_progress(@"Calculating size of $(items.length) items...", 0, 0);
                int64 total_size = 0;
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    if (items.length > 1) {
                        dlg.update_progress(@"Calculating size ($(i + 1)/$(items.length)): $(items[i].display_name)", 0, 0);
                    }
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

                if (!cancellable.is_cancelled()) {
                    AppLogger.info("FileOperation", @"Multi-copy completed successfully: $(items.length) items");
                    if (active_panel != null) {
                        active_panel.clear_tags();
                    }
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("FileOperation", @"Multi-copy cancelled: $(items.length) items");
                } else {
                    AppLogger.error("FileOperation", @"Multi-copy failed: $(items.length) items", e.message);
                    show_error_dialog("Copy Error", FileOperationService.format_error(e, "copy"));
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private void on_shift_f5_symlink() {
            if (active_panel == null) return;

            var tagged_items = active_panel.get_tagged_items();
            var opp = get_opposite_panel();
            File? dest_dir = opp.current_directory;

            if (tagged_items.length > 0) {
                if (dest_dir == null) {
                    show_error_dialog("Symlink Error", "Opposite panel has no directory open.");
                    return;
                }
                if (active_panel.current_directory != null && dest_dir.equal(active_panel.current_directory)) {
                    show_error_dialog("Symlink Error", "Cannot create symbolic links in the same directory with identical names.");
                    return;
                }

                string dest_path = dest_dir.get_path();
                if (dest_path == null) dest_path = dest_dir.get_parse_name();

                var dialog = new Adw.AlertDialog("Create Symbolic Links", @"Create $(tagged_items.length) symbolic links in:\n$dest_path");
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("create", "Create");
                dialog.set_default_response("create");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "create") {
                        do_symlink_multiple_items.begin(tagged_items, dest_dir);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
                return;
            }

            var item = active_panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Symlink", "Please select a file or folder to create a symbolic link.");
                return;
            }

            File default_dest_dir = (dest_dir != null) ? dest_dir : active_panel.current_directory;
            File default_target_file = default_dest_dir.get_child(item.name);

            string default_dest_path = default_target_file.get_path();
            if (default_dest_path == null) {
                default_dest_path = default_target_file.get_parse_name();
            }

            var dialog = new Adw.AlertDialog("Create Symbolic Link", @"Create symbolic link to '$(item.display_name)' at:");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("create", "Create");
            dialog.set_default_response("create");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED);

            var entry = new Gtk.Entry();
            entry.text = default_dest_path;
            entry.margin_start = 12;
            entry.margin_end = 12;
            entry.margin_top = 8;
            entry.margin_bottom = 8;
            dialog.set_extra_child(entry);

            bool action_executed = false;

            entry.activate.connect(() => {
                if (action_executed) return;
                action_executed = true;
                string dest_input = entry.text.strip();
                dialog.force_close();
                if (dest_input.length > 0) {
                    prompt_execute_symlink.begin(item, dest_input);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (action_executed) return;
                if (resp == "create") {
                    action_executed = true;
                    string dest_input = entry.text.strip();
                    if (dest_input.length > 0) {
                        prompt_execute_symlink.begin(item, dest_input);
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

        private async void prompt_execute_symlink(FileItem item, string dest_input) {
            File? dest_target = yield resolve_dest_file_async(item, dest_input, "Symlink");
            if (dest_target == null) return;

            if (dest_target.equal(item.file)) {
                show_error_dialog("Symlink Error", "Destination cannot be the same as the source file.");
                return;
            }

            bool dest_exists = false;
            try {
                var info = yield dest_target.query_info_async(
                    FileAttribute.STANDARD_TYPE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    Priority.DEFAULT,
                    null
                );
                dest_exists = (info != null);
            } catch (Error e) {
                dest_exists = false;
            }

            string target_path = (item.file.get_path() != null) ? item.file.get_path() : item.file.get_uri();

            if (dest_exists) {
                yield wait_for_dialogs_to_clear();
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
                        do_create_symlink.begin(dest_target, target_path, true);
                    } else {
                        if (active_panel != null) active_panel.grab_focus_to_list();
                    }
                });
            } else {
                yield do_create_symlink(dest_target, target_path, false);
            }
        }

        private async void do_create_symlink(File dest, string target_path, bool overwrite) {
            var cancellable = new Cancellable();
            try {
                yield FileOperationService.create_symbolic_link(
                    dest,
                    target_path,
                    overwrite,
                    cancellable
                );
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            } catch (Error e) {
                if (!e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_error_dialog("Symlink Error", FileOperationService.format_error(e, "create symbolic link"));
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private async void do_symlink_multiple_items(GenericArray<FileItem> items, File dest_dir) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Creating $(items.length) symbolic links", cancellable);
            attach_progress_dialog(dlg);

            try {
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    var dest_child = dest_dir.get_child(it.name);
                    string target_path = (it.file.get_path() != null) ? it.file.get_path() : it.file.get_uri();
                    dlg.update_items_progress(it.name, i + 1, items.length);

                    yield FileOperationService.create_symbolic_link(
                        dest_child,
                        target_path,
                        true,
                        cancellable
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
                    show_error_dialog("Symlink Error", FileOperationService.format_error(e, "create symbolic link"));
                }
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private void on_f6_move() {
            if (active_panel == null) return;

            if (active_panel.is_archive_location) {
                show_error_dialog("Move Error", "Moving files from archives is not supported.");
                return;
            }

            if (active_panel.is_trash_location) {
                prompt_restore_trash(active_panel);
                return;
            }

            var tagged_items = active_panel.get_tagged_items();
            var opp = get_opposite_panel();
            File? dest_dir = opp.current_directory;

            if (dest_dir != null && dest_dir.get_uri_scheme() == "archive") {
                show_error_dialog("Move Error", "Moving files directly into an archive is not supported.");
                return;
            }

            if (dest_dir != null && dest_dir.get_uri_scheme() == "trash") {
                show_error_dialog("Move Error", "Cannot move items into Trash this way. Use Delete (F8) to move items to Trash.");
                return;
            }

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

            bool action_executed = false;

            entry.activate.connect(() => {
                if (action_executed) return;
                action_executed = true;
                string dest_input = entry.text.strip();
                dialog.force_close();
                if (dest_input.length > 0) {
                    prompt_execute_move.begin(item, dest_input);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (action_executed) return;
                if (resp == "move") {
                    action_executed = true;
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

            bool action_executed = false;

            entry.activate.connect(() => {
                if (action_executed) return;
                action_executed = true;
                string new_name = entry.text.strip();
                dialog.force_close();
                if (new_name.length > 0 && new_name != item.display_name) {
                    prompt_execute_rename.begin(item, new_name);
                }
            });

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (action_executed) return;
                if (resp == "rename") {
                    action_executed = true;
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

            bool dest_exists = yield FileOperationService.file_exists_async(dest_target);
            if (dest_exists) {
                yield wait_for_dialogs_to_clear();
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
            File? dest_target = yield resolve_dest_file_async(item, dest_input, "Move");
            if (dest_target == null) return;

            if (dest_target.equal(item.file)) {
                show_error_dialog("Move Error", "Source and destination cannot be the same.");
                return;
            }

            bool dest_exists = yield FileOperationService.file_exists_async(dest_target);
            if (dest_exists) {
                yield wait_for_dialogs_to_clear();
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
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Moving $(source.get_basename())", cancellable);
            var disks = DriveQueueManager.get_required_disks(source, dest);
            register_operation(dlg, disks);

            var tracker = new CopyProgressTracker();
            AppLogger.info("FileOperation", @"Move requested: '$(source.get_basename())' -> '$(dest.get_path() ?? dest.get_uri())'");
            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

                int64 total_size = yield FileOperationService.calculate_total_size(source, cancellable);
                tracker.total_bytes = total_size;
                dlg.update_progress(source.get_basename(), 0, total_size);

                yield FileOperationService.move_file_or_dir(
                    source,
                    dest,
                    overwrite,
                    cancellable,
                    (cur_filename, current_b, total_b) => {
                        dlg.update_progress(cur_filename, current_b, total_b);
                    },
                    tracker
                );
                AppLogger.info("FileOperation", @"Move completed successfully: '$(source.get_basename())'");
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("FileOperation", @"Move cancelled: '$(source.get_basename())'");
                } else {
                    AppLogger.error("FileOperation", @"Move failed: '$(source.get_basename())'", e.message);
                    show_error_dialog("Move Error", FileOperationService.format_error(e, "move"));
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private async void do_move_multiple_items(GenericArray<FileItem> items, File dest_dir) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Moving $(items.length) items", cancellable);
            var disks = DriveQueueManager.get_required_disks_multi(items, dest_dir);
            register_operation(dlg, disks);
            var tracker = new CopyProgressTracker();
            AppLogger.info("FileOperation", @"Multi-move requested: $(items.length) items -> '$(dest_dir.get_path() ?? dest_dir.get_uri())'");
            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

                dlg.update_progress(@"Calculating size of $(items.length) items...", 0, 0);
                int64 total_size = 0;
                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    if (items.length > 1) {
                        dlg.update_progress(@"Calculating size ($(i + 1)/$(items.length)): $(items[i].display_name)", 0, 0);
                    }
                    total_size += yield FileOperationService.calculate_total_size(items[i].file, cancellable);
                }
                tracker.total_bytes = total_size;
                dlg.update_progress(@"Starting move...", 0, total_size);

                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    var dest_child = dest_dir.get_child(it.name);

                    yield FileOperationService.move_file_or_dir(
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

                if (!cancellable.is_cancelled()) {
                    AppLogger.info("FileOperation", @"Multi-move completed successfully: $(items.length) items");
                    if (active_panel != null) {
                        active_panel.clear_tags();
                    }
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("FileOperation", @"Multi-move cancelled: $(items.length) items");
                } else {
                    AppLogger.error("FileOperation", @"Multi-move failed: $(items.length) items", e.message);
                    show_error_dialog("Move Error", FileOperationService.format_error(e, "move"));
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                left_panel.refresh();
                right_panel.refresh();
                if (active_panel != null) active_panel.grab_focus_to_list();
            }
        }

        private async File? resolve_dest_file_async(FileItem item, string dest_input, string op_name, Cancellable? cancellable = null) {
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

            // Check if the input specifies an existing directory directly (non-blocking async)
            try {
                var info = yield dest_file.query_info_async(
                    FileAttribute.STANDARD_TYPE,
                    FileQueryInfoFlags.NONE,
                    Priority.DEFAULT,
                    cancellable
                );
                if (info.get_file_type() == FileType.DIRECTORY) {
                    return dest_file.get_child(item.name);
                }
                return dest_file;
            } catch (Error e) {
                // dest_file does not exist or query failed
            }

            // If destination does not exist, verify that its parent directory exists
            var parent = dest_file.get_parent();
            if (parent != null) {
                try {
                    yield parent.query_info_async(
                        FileAttribute.STANDARD_TYPE,
                        FileQueryInfoFlags.NONE,
                        Priority.DEFAULT,
                        cancellable
                    );
                } catch (Error e) {
                    string parent_path = parent.get_path();
                    if (parent_path == null) parent_path = parent.get_parse_name();
                    show_error_dialog(@"$op_name Error", @"The destination directory does not exist: $parent_path");
                    return null;
                }
            }

            return dest_file;
        }

        // =========================================================================
        // Trash Operations: Restore & Empty Trash
        // =========================================================================

        private void on_panel_restore_requested(FilePanel panel) {
            prompt_restore_trash(panel);
        }

        private void prompt_restore_trash(FilePanel panel) {
            var tagged = panel.get_tagged_items();
            if (tagged.length > 0) {
                var dialog = new Adw.AlertDialog(
                    "Restore Items",
                    @"Restore $(tagged.length) selected items from Trash to their original locations?"
                );
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("restore", "Restore");
                dialog.set_default_response("restore");
                dialog.set_close_response("cancel");
                dialog.set_response_appearance("restore", Adw.ResponseAppearance.SUGGESTED);

                dialog.choose.begin(this, null, (obj, res) => {
                    string resp = dialog.choose.end(res);
                    if (resp == "restore") {
                        do_restore_multiple_items.begin(panel, tagged);
                    } else {
                        panel.grab_focus_to_list();
                    }
                });
                return;
            }

            var item = panel.get_selected_item();
            if (item == null || item.is_parent_dir) {
                show_error_dialog("Restore", "Please select a file or folder to restore.");
                return;
            }

            on_panel_restore_item_requested(panel, item);
        }

        private void on_panel_restore_item_requested(FilePanel panel, FileItem item) {
            string orig_path = item.trash_orig_path;
            if (orig_path == null || orig_path.length == 0) {
                orig_path = Path.build_filename(Environment.get_home_dir(), item.name);
            }

            string body = item.trash_orig_path != null
                ? @"Restore '$(item.display_name)' to its original location?\n\n$orig_path"
                : @"Restore '$(item.display_name)' from Trash to your Home folder?\n\n$orig_path";

            var dialog = new Adw.AlertDialog("Restore from Trash", body);
            dialog.add_response("cancel", "Cancel");

            if (item.is_dir) {
                dialog.add_response("open", "Open Folder");
            }

            dialog.add_response("restore", "Restore");
            dialog.set_default_response("restore");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("restore", Adw.ResponseAppearance.SUGGESTED);

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "restore") {
                    prompt_execute_restore_single.begin(panel, item, orig_path);
                } else if (resp == "open") {
                    panel.load_directory(item.file);
                } else {
                    panel.grab_focus_to_list();
                }
            });
        }

        private async void prompt_execute_restore_single(FilePanel panel, FileItem item, string orig_path) {
            var dest_file = File.new_for_path(orig_path);
            bool dest_exists = yield FileOperationService.file_exists_async(dest_file);
            if (dest_exists) {
                yield wait_for_dialogs_to_clear();
                var conflict_dlg = new Adw.AlertDialog(
                    "File Already Exists",
                    @"A file or folder already exists at:\n$orig_path\n\nDo you want to overwrite it?"
                );
                conflict_dlg.add_response("cancel", "Cancel");
                conflict_dlg.add_response("overwrite", "Overwrite");
                conflict_dlg.set_default_response("cancel");
                conflict_dlg.set_close_response("cancel");
                conflict_dlg.set_response_appearance("overwrite", Adw.ResponseAppearance.DESTRUCTIVE);

                conflict_dlg.choose.begin(this, null, (obj, res) => {
                    string resp = conflict_dlg.choose.end(res);
                    if (resp == "overwrite") {
                        do_restore_single_item.begin(panel, item, orig_path, true);
                    } else {
                        panel.grab_focus_to_list();
                    }
                });
            } else {
                yield do_restore_single_item(panel, item, orig_path, false);
            }
        }

        private async void do_restore_single_item(FilePanel panel, FileItem item, string orig_path, bool overwrite) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Restoring $(item.display_name)", cancellable);
            var dest_file = File.new_for_path(orig_path);
            var disks = DriveQueueManager.get_required_disks(item.file, dest_file);
            register_operation(dlg, disks);
            AppLogger.info("Trash", @"Restore requested: '$(item.display_name)' -> '$orig_path'");
            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

                dlg.update_progress(item.display_name, 0, 1);
                yield FileOperationService.restore_trash_file(item.file, orig_path, overwrite, cancellable);
                AppLogger.info("Trash", @"Restore completed successfully: '$(item.display_name)'");
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("Trash", @"Restore cancelled: '$(item.display_name)'");
                } else {
                    AppLogger.error("Trash", @"Restore failed: '$(item.display_name)'", e.message);
                    show_error_dialog("Restore Error", FileOperationService.format_error(e, "restore"));
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                panel.refresh();
                var opp = (panel == left_panel) ? right_panel : left_panel;
                opp.refresh();
                panel.grab_focus_to_list();
            }
        }

        private async void do_restore_multiple_items(FilePanel panel, GenericArray<FileItem> items) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog(@"Restoring $(items.length) items from Trash", cancellable);

            string first_dest_path = (items.length > 0 && items[0].trash_orig_path != null && items[0].trash_orig_path.length > 0)
                ? items[0].trash_orig_path
                : Environment.get_home_dir();
            var dest_file = File.new_for_path(first_dest_path);
            var disks = DriveQueueManager.get_required_disks(items.length > 0 ? items[0].file : null, dest_file);
            register_operation(dlg, disks);
            AppLogger.info("Trash", @"Multi-restore requested: $(items.length) items");
            try {
                yield DriveQueueManager.get_instance().acquire_disks_async(disks, dlg, cancellable);

                for (int i = 0; i < items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var it = items[i];
                    dlg.update_progress(it.display_name, i + 1, items.length);

                    string orig_path = it.trash_orig_path;
                    if (orig_path == null || orig_path.length == 0) {
                        orig_path = Path.build_filename(Environment.get_home_dir(), it.name);
                    }

                    yield FileOperationService.restore_trash_file(it.file, orig_path, true, cancellable);
                }

                if (!cancellable.is_cancelled()) {
                    AppLogger.info("Trash", @"Multi-restore completed successfully: $(items.length) items");
                    panel.clear_tags();
                }
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.CANCELLED)) {
                    AppLogger.info("Trash", @"Multi-restore cancelled: $(items.length) items");
                } else {
                    AppLogger.error("Trash", @"Multi-restore failed: $(items.length) items", e.message);
                    show_error_dialog("Restore Error", FileOperationService.format_error(e, "restore"));
                }
            } finally {
                DriveQueueManager.get_instance().release_disks(disks, dlg);
                dlg.finish();
                panel.refresh();
                var opp = (panel == left_panel) ? right_panel : left_panel;
                opp.refresh();
                panel.grab_focus_to_list();
            }
        }

        private void on_panel_empty_trash_requested(FilePanel panel) {
            var dialog = new Adw.AlertDialog(
                "Empty Trash?",
                "All items in the Trash will be permanently deleted. This action cannot be undone."
            );
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("empty", "Empty Trash");
            dialog.set_default_response("cancel");
            dialog.set_close_response("cancel");
            dialog.set_response_appearance("empty", Adw.ResponseAppearance.DESTRUCTIVE);

            dialog.choose.begin(this, null, (obj, res) => {
                string resp = dialog.choose.end(res);
                if (resp == "empty") {
                    do_empty_trash.begin(panel);
                } else {
                    panel.grab_focus_to_list();
                }
            });
        }

        private async void do_empty_trash(FilePanel panel) {
            var cancellable = new Cancellable();
            var dlg = new OperationProgressDialog("Emptying Trash...", cancellable);
            attach_progress_dialog(dlg);

            try {
                yield FileOperationService.empty_trash(cancellable);
                dlg.finish();

                panel.clear_tags();
                panel.refresh();
                var opp = (panel == left_panel) ? right_panel : left_panel;
                if (opp.is_trash_location) {
                    opp.clear_tags();
                    opp.refresh();
                }
                panel.grab_focus_to_list();
            } catch (Error e) {
                dlg.finish();
                if (!e.matches(IOError.quark(), IOError.CANCELLED)) {
                    show_error_dialog("Empty Trash Error", FileOperationService.format_error(e, "empty trash"));
                }
                panel.refresh();
                panel.grab_focus_to_list();
            }
        }

        public void save_state() {
            var config = ConfigManager.get_instance();
            left_panel.save_columns_to_config();
            right_panel.save_columns_to_config();

            int cur_w, cur_h;
            get_default_size(out cur_w, out cur_h);
            if (cur_w <= 0) cur_w = get_width();
            if (cur_h <= 0) cur_h = get_height();

            config.window_width = cur_w > 0 ? cur_w : 1024;
            config.window_height = cur_h > 0 ? cur_h : 680;
            config.is_maximized = maximized;
            if (saved_dual_paned_position > 0) {
                config.paned_position = saved_dual_paned_position;
            } else {
                config.paned_position = paned.position;
            }
            config.active_pane = (active_panel == right_panel) ? "right" : "left";
            int total_h = vertical_paned.get_height();
            int v_pos = vertical_paned.position;
            if (total_h > 0 && v_pos > 0 && total_h > v_pos) {
                int ch = total_h - v_pos;
                if (ch >= 80 && ch <= 1600) {
                    config.console_height = ch;
                }
            }

            // Left panel state
            config.left_tabs = left_panel.get_tab_paths();
            config.left_tab_titles = left_panel.get_tab_titles();
            config.left_pinned_tabs = left_panel.get_tab_pinned_states();
            config.left_sort_cols = left_panel.get_tab_sort_cols();
            config.left_sort_orders = left_panel.get_tab_sort_orders();
            config.left_view_modes = left_panel.get_tab_view_modes();
            config.left_active_tab = left_panel.get_active_tab_index();
            config.left_brief_view = left_panel.is_brief_view;
            config.show_hidden = left_panel.show_hidden;
            config.left_show_hidden = left_panel.show_hidden;

            // Right panel state
            config.right_tabs = right_panel.get_tab_paths();
            config.right_tab_titles = right_panel.get_tab_titles();
            config.right_pinned_tabs = right_panel.get_tab_pinned_states();
            config.right_sort_cols = right_panel.get_tab_sort_cols();
            config.right_sort_orders = right_panel.get_tab_sort_orders();
            config.right_view_modes = right_panel.get_tab_view_modes();
            config.right_active_tab = right_panel.get_active_tab_index();
            config.right_brief_view = right_panel.is_brief_view;
            config.right_show_hidden = right_panel.show_hidden;

            config.save();
        }

        public void toggle_show_hidden() {
            var config = ConfigManager.get_instance();
            bool new_val = !config.show_hidden;
            config.show_hidden = new_val;
            config.left_show_hidden = new_val;
            config.right_show_hidden = new_val;
            config.save();

            left_panel.set_show_hidden(new_val);
            right_panel.set_show_hidden(new_val);
        }

        private bool on_close_requested() {
            if (background_tasks != null && background_tasks.length > 0) {
                var alert = new Adw.AlertDialog(
                    "Operations in Progress",
                    @"There $(background_tasks.length == 1 ? "is 1 background operation" : @"are $(background_tasks.length) background operations") running. Quitting will cancel these operations."
                );
                alert.add_response("cancel", "Cancel");
                alert.add_response("quit", "Quit Anyway");
                alert.set_default_response("cancel");
                alert.set_close_response("cancel");
                alert.set_response_appearance("quit", Adw.ResponseAppearance.DESTRUCTIVE);

                alert.choose.begin(this, null, (obj, res) => {
                    string resp = alert.choose.end(res);
                    if (resp == "quit") {
                        for (int i = 0; i < background_tasks.length; i++) {
                            background_tasks[i].cancellable.cancel();
                        }
                        background_tasks.remove_range(0, background_tasks.length);
                        save_state();
                        this.destroy();
                    }
                });
                return true;
            }
            if (escape_sequence_timeout_id != 0) {
                Source.remove(escape_sequence_timeout_id);
                escape_sequence_timeout_id = 0;
            }
            save_state();
            return false;
        }

        public void prompt_preferences_dialog() {
            PreferencesDialog.show(this, this);
        }

        public void prompt_filesystem_repair(LocationItem item, string? initial_error = null) {
            FilesystemRepairDialog.show(this, item, initial_error);
        }

        public void open_terminal_with_command(string command) {
            set_console_visible(true);
            if (vte_terminal != null) {
                vte_terminal.feed_child((command + "\n").data);
                vte_terminal.grab_focus();
            }
        }

        public void apply_preferences() {
            var config = ConfigManager.get_instance();
            if (fn_bar != null) {
                fn_bar.visible = config.show_function_bar;
            }
            left_panel.update_brief_column_width();
            right_panel.update_brief_column_width();
            left_panel.update_grid_tile_size();
            right_panel.update_grid_tile_size();
            apply_app_theme();
            apply_font_styles();
            apply_terminal_font();
            apply_terminal_theme();
            FilesystemRepairDialog.apply_active_console_theme();
        }

        public void show_about_dialog(Gtk.Widget? parent_widget = null) {
            var about = new Adw.AboutDialog();
            about.application_name = "Vala Commander";
            about.application_icon = "org.vcmd.ValaCommander";
            about.developer_name = "Vala Commander Contributors";
            about.version = ConfigManager.get_version(true);
            about.comments = "A lightweight, responsive, modern dual-pane file manager for Linux, blending the keyboard-driven speed of Midnight Commander with modern GTK4/Libadwaita GUI aesthetics.";
            about.website = "https://github.com/ijin82/vcmd";
            about.issue_url = "https://github.com/ijin82/vcmd/issues";
            about.license_type = Gtk.License.GPL_3_0;
            about.copyright = "© 2025-2026 Vala Commander Developers";
            about.present(parent_widget != null ? parent_widget : this);
        }

        public override void unmap() {
            save_state();
            base.unmap();
        }
    }
}
