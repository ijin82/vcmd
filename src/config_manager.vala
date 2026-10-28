namespace VCommander {

    public class ConfigManager : Object {
        private static ConfigManager? _instance = null;
        public static ConfigManager get_instance() {
            if (_instance == null) {
                _instance = new ConfigManager();
            }
            return _instance;
        }

        private string config_path;
        private KeyFile key_file;

        // Configuration fields
        public int window_width { get; set; default = 1024; }
        public int window_height { get; set; default = 680; }
        public bool is_maximized { get; set; default = false; }
        public int paned_position { get; set; default = 512; }
        public string active_pane { get; set; default = "left"; }

        public string[] left_tabs { get; set; }
        public string[] left_tab_titles { get; set; }
        public int left_active_tab { get; set; default = 0; }
        public bool left_brief_view { get; set; default = false; }
        public bool left_show_hidden { get; set; default = false; }

        public string[] right_tabs { get; set; }
        public string[] right_tab_titles { get; set; }
        public int right_active_tab { get; set; default = 0; }
        public bool right_brief_view { get; set; default = false; }
        public bool right_show_hidden { get; set; default = false; }

        public bool show_path_toolbar { get; set; default = true; }
        public bool show_function_bar { get; set; default = true; }
        public int brief_column_width { get; set; default = 180; }
        public string panel_font_name { get; set; default = "Monospace"; }
        public int panel_font_size { get; set; default = 11; }
        public string command_shell { get; set; default = "/bin/bash"; }
        public string[] col_order { get; set; }
        public int col_width_name { get; set; default = 0; }
        public int col_width_type { get; set; default = 80; }
        public int col_width_size { get; set; default = 110; }
        public int col_width_mtime { get; set; default = 175; }

        private ConfigManager() {
            string config_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd");
            config_path = Path.build_filename(config_dir, "config");
            key_file = new KeyFile();

            // Default tabs
            string home = Environment.get_home_dir();
            left_tabs = new string[] { home };
            left_tab_titles = new string[] { "" };
            right_tabs = new string[] { home };
            right_tab_titles = new string[] { "" };
            col_order = new string[] { "name", "type", "size", "mtime" };

            load();
        }

        public void load() {
            var file = File.new_for_path(config_path);
            if (!file.query_exists()) {
                return;
            }

            try {
                key_file.load_from_file(config_path, KeyFileFlags.NONE);

                // Window settings
                if (key_file.has_key("Window", "Width")) {
                    window_width = key_file.get_integer("Window", "Width");
                }
                if (key_file.has_key("Window", "Height")) {
                    window_height = key_file.get_integer("Window", "Height");
                }
                if (key_file.has_key("Window", "IsMaximized")) {
                    is_maximized = key_file.get_boolean("Window", "IsMaximized");
                }
                if (key_file.has_key("Window", "PanedPosition")) {
                    paned_position = key_file.get_integer("Window", "PanedPosition");
                }
                if (key_file.has_key("Window", "ActivePane")) {
                    active_pane = key_file.get_string("Window", "ActivePane");
                }

                // General settings
                if (key_file.has_key("General", "ShowPathToolbar")) {
                    show_path_toolbar = key_file.get_boolean("General", "ShowPathToolbar");
                }
                if (key_file.has_key("General", "ShowFunctionBar")) {
                    show_function_bar = key_file.get_boolean("General", "ShowFunctionBar");
                }
                if (key_file.has_key("General", "BriefColumnWidth")) {
                    brief_column_width = key_file.get_integer("General", "BriefColumnWidth");
                    if (brief_column_width < 100) brief_column_width = 100;
                    if (brief_column_width > 800) brief_column_width = 800;
                }
                if (key_file.has_key("General", "PanelFontName")) {
                    panel_font_name = key_file.get_string("General", "PanelFontName");
                }
                if (key_file.has_key("General", "PanelFontSize")) {
                    panel_font_size = key_file.get_integer("General", "PanelFontSize");
                    if (panel_font_size < 6) panel_font_size = 6;
                    if (panel_font_size > 72) panel_font_size = 72;
                }
                if (key_file.has_key("General", "CommandShell")) {
                    string shell = key_file.get_string("General", "CommandShell").strip();
                    if (shell.length > 0) {
                        command_shell = shell;
                    }
                }
                if (key_file.has_key("Columns", "Order")) {
                    var order = key_file.get_string_list("Columns", "Order");
                    if (order.length > 0) {
                        col_order = order;
                    }
                }
                if (key_file.has_key("Columns", "WidthName")) {
                    col_width_name = key_file.get_integer("Columns", "WidthName");
                }
                if (key_file.has_key("Columns", "WidthType")) {
                    col_width_type = key_file.get_integer("Columns", "WidthType");
                }
                if (key_file.has_key("Columns", "WidthSize")) {
                    col_width_size = key_file.get_integer("Columns", "WidthSize");
                }
                if (key_file.has_key("Columns", "WidthMTime")) {
                    col_width_mtime = key_file.get_integer("Columns", "WidthMTime");
                }

                // Left Panel
                if (key_file.has_key("LeftPanel", "Tabs")) {
                    var tabs = key_file.get_string_list("LeftPanel", "Tabs");
                    if (tabs.length > 0) {
                        left_tabs = tabs;
                    }
                }
                if (key_file.has_key("LeftPanel", "TabTitles")) {
                    var titles = key_file.get_string_list("LeftPanel", "TabTitles");
                    left_tab_titles = titles;
                }
                if (key_file.has_key("LeftPanel", "ActiveTab")) {
                    left_active_tab = key_file.get_integer("LeftPanel", "ActiveTab");
                }
                if (key_file.has_key("LeftPanel", "BriefView")) {
                    left_brief_view = key_file.get_boolean("LeftPanel", "BriefView");
                }
                if (key_file.has_key("LeftPanel", "ShowHidden")) {
                    left_show_hidden = key_file.get_boolean("LeftPanel", "ShowHidden");
                }

                // Right Panel
                if (key_file.has_key("RightPanel", "Tabs")) {
                    var tabs = key_file.get_string_list("RightPanel", "Tabs");
                    if (tabs.length > 0) {
                        right_tabs = tabs;
                    }
                }
                if (key_file.has_key("RightPanel", "TabTitles")) {
                    var titles = key_file.get_string_list("RightPanel", "TabTitles");
                    right_tab_titles = titles;
                }
                if (key_file.has_key("RightPanel", "ActiveTab")) {
                    right_active_tab = key_file.get_integer("RightPanel", "ActiveTab");
                }
                if (key_file.has_key("RightPanel", "BriefView")) {
                    right_brief_view = key_file.get_boolean("RightPanel", "BriefView");
                }
                if (key_file.has_key("RightPanel", "ShowHidden")) {
                    right_show_hidden = key_file.get_boolean("RightPanel", "ShowHidden");
                }
            } catch (Error e) {
                warning("Failed to load configuration: %s", e.message);
            }
        }

        public void save() {
            try {
                // Window
                key_file.set_integer("Window", "Width", window_width);
                key_file.set_integer("Window", "Height", window_height);
                key_file.set_boolean("Window", "IsMaximized", is_maximized);
                key_file.set_integer("Window", "PanedPosition", paned_position);
                key_file.set_string("Window", "ActivePane", active_pane);

                // General
                key_file.set_boolean("General", "ShowPathToolbar", show_path_toolbar);
                key_file.set_boolean("General", "ShowFunctionBar", show_function_bar);
                key_file.set_integer("General", "BriefColumnWidth", brief_column_width);
                key_file.set_string("General", "PanelFontName", panel_font_name);
                key_file.set_integer("General", "PanelFontSize", panel_font_size);
                key_file.set_string("General", "CommandShell", command_shell);

                // Columns
                if (col_order != null && col_order.length > 0) {
                    key_file.set_string_list("Columns", "Order", col_order);
                }
                key_file.set_integer("Columns", "WidthName", col_width_name);
                key_file.set_integer("Columns", "WidthType", col_width_type);
                key_file.set_integer("Columns", "WidthSize", col_width_size);
                key_file.set_integer("Columns", "WidthMTime", col_width_mtime);

                // Left Panel
                key_file.set_string_list("LeftPanel", "Tabs", left_tabs);
                if (left_tab_titles != null) {
                    key_file.set_string_list("LeftPanel", "TabTitles", left_tab_titles);
                }
                key_file.set_integer("LeftPanel", "ActiveTab", left_active_tab);
                key_file.set_boolean("LeftPanel", "BriefView", left_brief_view);
                key_file.set_boolean("LeftPanel", "ShowHidden", left_show_hidden);

                // Right Panel
                key_file.set_string_list("RightPanel", "Tabs", right_tabs);
                if (right_tab_titles != null) {
                    key_file.set_string_list("RightPanel", "TabTitles", right_tab_titles);
                }
                key_file.set_integer("RightPanel", "ActiveTab", right_active_tab);
                key_file.set_boolean("RightPanel", "BriefView", right_brief_view);
                key_file.set_boolean("RightPanel", "ShowHidden", right_show_hidden);

                // Ensure directory exists
                string config_dir = Path.get_dirname(config_path);
                var dir = File.new_for_path(config_dir);
                if (!dir.query_exists()) {
                    dir.make_directory_with_parents(null);
                }

                string data = key_file.to_data();
                FileUtils.set_contents(config_path, data);
            } catch (Error e) {
                warning("Failed to save configuration: %s", e.message);
            }
        }
    }
}
