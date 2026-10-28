namespace VCommander {

    public class PreferencesDialog : Object {
        private static Adw.PreferencesDialog? active_dialog = null;

        public static void show(Gtk.Window parent, MainWindow main_win) {
            if (active_dialog != null) {
                active_dialog.present(parent);
                return;
            }

            var config = ConfigManager.get_instance();

            var dialog = new Adw.PreferencesDialog();
            active_dialog = dialog;
            dialog.title = "Preferences";
            dialog.content_width = 600;
            dialog.content_height = 480;

            dialog.closed.connect(() => {
                active_dialog = null;
                if (main_win.active_panel != null) {
                    main_win.active_panel.grab_focus_to_list();
                }
            });

            var page = new Adw.PreferencesPage();

            // Panels & Interface Group
            var panel_group = new Adw.PreferencesGroup();
            panel_group.title = "Panels &amp; Interface";
            panel_group.description = "Options for file panels and navigation toolbar";

            var toolbar_row = new Adw.SwitchRow();
            toolbar_row.title = "Show path toolbar under tabs";
            toolbar_row.subtitle = "Display path input bar with navigation and view toggle buttons in each panel";
            toolbar_row.active = config.show_path_toolbar;

            toolbar_row.notify["active"].connect(() => {
                config.show_path_toolbar = toolbar_row.active;
                config.save();
                main_win.apply_preferences();
            });

            panel_group.add(toolbar_row);

            var fn_bar_row = new Adw.SwitchRow();
            fn_bar_row.title = "Show bottom function key bar (F1..F10)";
            fn_bar_row.subtitle = "Display the Midnight Commander function buttons row at the bottom of the window";
            fn_bar_row.active = config.show_function_bar;

            fn_bar_row.notify["active"].connect(() => {
                config.show_function_bar = fn_bar_row.active;
                config.save();
                main_win.apply_preferences();
            });

            panel_group.add(fn_bar_row);

            var column_width_row = new Adw.SpinRow.with_range(100, 800, 10);
            column_width_row.title = "Brief view column width (px)";
            column_width_row.subtitle = "Width in pixels for columns in brief view mode (100 - 800 px)";
            column_width_row.value = config.brief_column_width;

            column_width_row.notify["value"].connect(() => {
                config.brief_column_width = (int) column_width_row.value;
                config.save();
                main_win.apply_preferences();
            });

            panel_group.add(column_width_row);
            page.add(panel_group);

            // Fonts & Appearance Group
            var font_group = new Adw.PreferencesGroup();
            font_group.title = "Fonts &amp; Appearance";
            font_group.description = "Typography settings for dual-pane file lists and grids";

            var font_row = new Adw.ActionRow();
            font_row.title = "Panel font";
            font_row.subtitle = "Font family for file lists and grids";

            var font_dialog = new Gtk.FontDialog();
            var font_button = new Gtk.FontDialogButton(font_dialog);
            var initial_desc = Pango.FontDescription.from_string(@"$(config.panel_font_name) $(config.panel_font_size)");
            font_button.set_font_desc(initial_desc);
            font_button.valign = Gtk.Align.CENTER;

            font_row.add_suffix(font_button);
            font_row.activatable_widget = font_button;
            font_group.add(font_row);

            var font_size_row = new Adw.SpinRow.with_range(6, 36, 1);
            font_size_row.title = "Panel font size (pt)";
            font_size_row.subtitle = "Font size in points (6 - 36 pt)";
            font_size_row.value = config.panel_font_size;
            font_group.add(font_size_row);

            bool updating_font = false;

            font_button.notify["font-desc"].connect(() => {
                if (updating_font) return;
                updating_font = true;
                var desc = font_button.get_font_desc();
                if (desc != null) {
                    string? family = desc.get_family();
                    if (family != null && family.length > 0) {
                        config.panel_font_name = family;
                    }
                    int size = (int) (desc.get_size() / Pango.SCALE);
                    if (size >= 6 && size <= 72) {
                        config.panel_font_size = size;
                        font_size_row.value = size;
                    }
                    config.save();
                    main_win.apply_preferences();
                }
                updating_font = false;
            });

            font_size_row.notify["value"].connect(() => {
                if (updating_font) return;
                updating_font = true;
                config.panel_font_size = (int) font_size_row.value;
                var desc = Pango.FontDescription.from_string(@"$(config.panel_font_name) $(config.panel_font_size)");
                font_button.set_font_desc(desc);
                config.save();
                main_win.apply_preferences();
                updating_font = false;
            });

            page.add(font_group);

            // Terminal & Command Line Group
            var cmd_group = new Adw.PreferencesGroup();
            cmd_group.title = "Terminal &amp; Command Line";
            cmd_group.description = "Shell interpreter and environment for the bottom command bar";

            var shell_row = new Adw.EntryRow();
            shell_row.title = "Shell executable";
            shell_row.text = config.command_shell;

            shell_row.notify["text"].connect(() => {
                string entered = shell_row.text.strip();
                config.command_shell = entered.length > 0 ? entered : "/bin/bash";
                config.save();
            });

            cmd_group.add(shell_row);
            page.add(cmd_group);

            // File Viewer & Editor Group (F3 / F4)
            var tools_group = new Adw.PreferencesGroup();
            tools_group.title = "Viewer &amp; Editor (F3 / F4)";
            tools_group.description = "External applications used to view (F3) and edit (F4) selected files";

            var viewer_row = new Adw.EntryRow();
            viewer_row.title = "File viewer command (F3)";
            viewer_row.text = config.viewer_command;

            viewer_row.notify["text"].connect(() => {
                string entered = viewer_row.text.strip();
                config.viewer_command = entered.length > 0 ? entered : ConfigManager.detect_default_editor();
                config.save();
            });
            tools_group.add(viewer_row);

            var editor_row = new Adw.EntryRow();
            editor_row.title = "File editor command (F4)";
            editor_row.text = config.editor_command;

            editor_row.notify["text"].connect(() => {
                string entered = editor_row.text.strip();
                config.editor_command = entered.length > 0 ? entered : ConfigManager.detect_default_editor();
                config.save();
            });
            tools_group.add(editor_row);

            page.add(tools_group);

            dialog.add(page);
            dialog.present(parent);
        }
    }
}
