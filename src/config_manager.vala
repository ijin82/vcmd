namespace VCommander {

    public class BookmarkItem : Object {
        public string name { get; set; default = ""; }
        public string uri_or_path { get; set; default = ""; }

        public BookmarkItem(string name, string uri_or_path) {
            this.name = (name != null) ? name.strip() : "";
            this.uri_or_path = (uri_or_path != null) ? uri_or_path.strip() : "";
        }

        public string get_display_title() {
            string trimmed = (name != null) ? name.strip() : "";
            return (trimmed.length > 0) ? trimmed : uri_or_path;
        }
    }

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
        public string[] left_sort_cols { get; set; }
        public string[] left_sort_orders { get; set; }
        public string[]? left_view_modes { get; set; default = null; }
        public int left_active_tab { get; set; default = 0; }
        public bool left_brief_view { get; set; default = false; }
        public bool left_show_hidden { get; set; default = false; }

        public string[] right_tabs { get; set; }
        public string[] right_tab_titles { get; set; }
        public string[] right_sort_cols { get; set; }
        public string[] right_sort_orders { get; set; }
        public string[]? right_view_modes { get; set; default = null; }
        public int right_active_tab { get; set; default = 0; }
        public bool right_brief_view { get; set; default = false; }
        public bool right_show_hidden { get; set; default = false; }

        public bool show_path_toolbar { get; set; default = true; }
        public bool show_function_bar { get; set; default = true; }
        public bool show_hidden { get; set; default = false; }
        public int brief_column_width { get; set; default = 180; }
        public string panel_font_name { get; set; default = "Monospace"; }
        public int panel_font_size { get; set; default = 11; }
        public string command_shell { get; set; default = "/bin/bash"; }
        public string viewer_command { get; set; }
        public string editor_command { get; set; }
        public string[] col_order { get; set; }
        public int col_width_name { get; set; default = 0; }
        public int col_width_type { get; set; default = 80; }
        public int col_width_size { get; set; default = 110; }
        public int col_width_mtime { get; set; default = 175; }
        public string select_mask { get; set; default = "*"; }
        public bool select_mask_include_dirs { get; set; default = false; }
        public int bookmarks_dialog_width { get; set; default = 640; }
        public int bookmarks_dialog_height { get; set; default = 580; }

        public GenericArray<BookmarkItem> bookmarks { get; private set; }

        public static string detect_default_editor() {
            string[] candidates = {
                "gnome-text-editor",
                "gvim",
                "code",
                "gedit",
                "kate",
                "xed",
                "mousepad",
                "nano",
                "vim",
                "vi",
                "xdg-open"
            };

            foreach (var prog in candidates) {
                if (Environment.find_program_in_path(prog) != null) {
                    return prog;
                }
            }

            return "gnome-text-editor";
        }

        private ConfigManager() {
            string config_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd");
            config_path = Path.build_filename(config_dir, "config");
            key_file = new KeyFile();

            // Default tabs
            string home = Environment.get_home_dir();
            left_tabs = new string[] { home };
            left_tab_titles = new string[] { "" };
            left_sort_cols = new string[] { "name" };
            left_sort_orders = new string[] { "asc" };
            right_tabs = new string[] { home };
            right_tab_titles = new string[] { "" };
            right_sort_cols = new string[] { "name" };
            right_sort_orders = new string[] { "asc" };
            col_order = new string[] { "name", "size", "mtime" };

            viewer_command = detect_default_editor();
            editor_command = detect_default_editor();

            bookmarks = new GenericArray<BookmarkItem>();
            bookmarks.add(new BookmarkItem("Home", home));
            bookmarks.add(new BookmarkItem("Root", "/"));

            load();
        }

        public void add_bookmark(string name, string uri_or_path) {
            string trimmed_name = name.strip();
            if (trimmed_name.char_count() > 50) {
                trimmed_name = trimmed_name.substring(0, 50);
            }
            bookmarks.add(new BookmarkItem(trimmed_name, uri_or_path.strip()));
            save();
        }

        public void remove_bookmark(uint index) {
            if (index < bookmarks.length) {
                bookmarks.remove_index(index);
                save();
            }
        }

        public bool move_bookmark_up(uint index) {
            if (index > 0 && index < bookmarks.length) {
                var item = bookmarks.get(index);
                var prev = bookmarks.get(index - 1);
                bookmarks.set(index - 1, item);
                bookmarks.set(index, prev);
                save();
                return true;
            }
            return false;
        }

        public bool move_bookmark_down(uint index) {
            if (index + 1 < bookmarks.length) {
                var item = bookmarks.get(index);
                var next = bookmarks.get(index + 1);
                bookmarks.set(index + 1, item);
                bookmarks.set(index, next);
                save();
                return true;
            }
            return false;
        }

        public void update_bookmark_name(uint index, string new_name) {
            if (index < bookmarks.length) {
                var bm = bookmarks.get(index);
                string trimmed = (new_name != null) ? new_name.strip() : "";
                if (trimmed.char_count() > 50) {
                    trimmed = trimmed.substring(0, 50);
                }
                bm.name = trimmed;
                save();
            }
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
                if (key_file.has_key("General", "ShowHidden")) {
                    show_hidden = key_file.get_boolean("General", "ShowHidden");
                } else if (key_file.has_key("LeftPanel", "ShowHidden")) {
                    show_hidden = key_file.get_boolean("LeftPanel", "ShowHidden");
                }
                left_show_hidden = show_hidden;
                right_show_hidden = show_hidden;
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
                if (key_file.has_key("General", "ViewerCommand")) {
                    string vcmd = key_file.get_string("General", "ViewerCommand").strip();
                    if (vcmd.length > 0) {
                        viewer_command = vcmd;
                    }
                }
                if (key_file.has_key("General", "EditorCommand")) {
                    string ecmd = key_file.get_string("General", "EditorCommand").strip();
                    if (ecmd.length > 0) {
                        editor_command = ecmd;
                    }
                }
                if (key_file.has_key("General", "SelectMask")) {
                    string smask = key_file.get_string("General", "SelectMask");
                    if (smask.length > 0) {
                        select_mask = smask;
                    }
                }
                if (key_file.has_key("General", "SelectMaskIncludeDirs")) {
                    select_mask_include_dirs = key_file.get_boolean("General", "SelectMaskIncludeDirs");
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
                if (key_file.has_key("LeftPanel", "SortCols")) {
                    var scols = key_file.get_string_list("LeftPanel", "SortCols");
                    if (scols.length > 0) {
                        left_sort_cols = scols;
                    }
                }
                if (key_file.has_key("LeftPanel", "SortOrders")) {
                    var sorders = key_file.get_string_list("LeftPanel", "SortOrders");
                    if (sorders.length > 0) {
                        left_sort_orders = sorders;
                    }
                }
                if (key_file.has_key("LeftPanel", "ActiveTab")) {
                    left_active_tab = key_file.get_integer("LeftPanel", "ActiveTab");
                }
                if (key_file.has_key("LeftPanel", "ViewModes")) {
                    var vmodes = key_file.get_string_list("LeftPanel", "ViewModes");
                    if (vmodes.length > 0) {
                        left_view_modes = vmodes;
                    }
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
                if (key_file.has_key("RightPanel", "SortCols")) {
                    var scols = key_file.get_string_list("RightPanel", "SortCols");
                    if (scols.length > 0) {
                        right_sort_cols = scols;
                    }
                }
                if (key_file.has_key("RightPanel", "SortOrders")) {
                    var sorders = key_file.get_string_list("RightPanel", "SortOrders");
                    if (sorders.length > 0) {
                        right_sort_orders = sorders;
                    }
                }
                if (key_file.has_key("RightPanel", "ActiveTab")) {
                    right_active_tab = key_file.get_integer("RightPanel", "ActiveTab");
                }
                if (key_file.has_key("RightPanel", "ViewModes")) {
                    var vmodes = key_file.get_string_list("RightPanel", "ViewModes");
                    if (vmodes.length > 0) {
                        right_view_modes = vmodes;
                    }
                }
                if (key_file.has_key("RightPanel", "BriefView")) {
                    right_brief_view = key_file.get_boolean("RightPanel", "BriefView");
                }
                if (key_file.has_key("RightPanel", "ShowHidden")) {
                    right_show_hidden = key_file.get_boolean("RightPanel", "ShowHidden");
                }

                // Bookmarks
                if (key_file.has_group("Bookmarks") && key_file.has_key("Bookmarks", "Paths")) {
                    var paths = key_file.get_string_list("Bookmarks", "Paths");
                    string[] names = {};
                    if (key_file.has_key("Bookmarks", "Names")) {
                        names = key_file.get_string_list("Bookmarks", "Names");
                    }
                    bookmarks = new GenericArray<BookmarkItem>();
                    for (int i = 0; i < paths.length; i++) {
                        string p = paths[i];
                        string n = (i < names.length) ? names[i] : "";
                        bookmarks.add(new BookmarkItem(n, p));
                    }
                }
                if (key_file.has_group("Bookmarks")) {
                    if (key_file.has_key("Bookmarks", "DialogWidth")) {
                        int bw = key_file.get_integer("Bookmarks", "DialogWidth");
                        if (bw >= 400 && bw <= 3840) {
                            bookmarks_dialog_width = bw;
                        }
                    }
                    if (key_file.has_key("Bookmarks", "DialogHeight")) {
                        int bh = key_file.get_integer("Bookmarks", "DialogHeight");
                        if (bh >= 300 && bh <= 2160) {
                            bookmarks_dialog_height = bh;
                        }
                    }
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
                key_file.set_boolean("General", "ShowHidden", show_hidden);
                key_file.set_integer("General", "BriefColumnWidth", brief_column_width);
                key_file.set_string("General", "PanelFontName", panel_font_name);
                key_file.set_integer("General", "PanelFontSize", panel_font_size);
                key_file.set_string("General", "CommandShell", command_shell);
                key_file.set_string("General", "ViewerCommand", viewer_command.length > 0 ? viewer_command : detect_default_editor());
                key_file.set_string("General", "EditorCommand", editor_command.length > 0 ? editor_command : detect_default_editor());
                key_file.set_string("General", "SelectMask", select_mask.length > 0 ? select_mask : "*");
                key_file.set_boolean("General", "SelectMaskIncludeDirs", select_mask_include_dirs);

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
                if (left_sort_cols != null && left_sort_cols.length > 0) {
                    key_file.set_string_list("LeftPanel", "SortCols", left_sort_cols);
                }
                if (left_sort_orders != null && left_sort_orders.length > 0) {
                    key_file.set_string_list("LeftPanel", "SortOrders", left_sort_orders);
                }
                if (left_view_modes != null && left_view_modes.length > 0) {
                    key_file.set_string_list("LeftPanel", "ViewModes", left_view_modes);
                }
                key_file.set_integer("LeftPanel", "ActiveTab", left_active_tab);
                key_file.set_boolean("LeftPanel", "BriefView", left_brief_view);
                key_file.set_boolean("LeftPanel", "ShowHidden", left_show_hidden);

                // Right Panel
                key_file.set_string_list("RightPanel", "Tabs", right_tabs);
                if (right_tab_titles != null) {
                    key_file.set_string_list("RightPanel", "TabTitles", right_tab_titles);
                }
                if (right_sort_cols != null && right_sort_cols.length > 0) {
                    key_file.set_string_list("RightPanel", "SortCols", right_sort_cols);
                }
                if (right_sort_orders != null && right_sort_orders.length > 0) {
                    key_file.set_string_list("RightPanel", "SortOrders", right_sort_orders);
                }
                if (right_view_modes != null && right_view_modes.length > 0) {
                    key_file.set_string_list("RightPanel", "ViewModes", right_view_modes);
                }
                key_file.set_integer("RightPanel", "ActiveTab", right_active_tab);
                key_file.set_boolean("RightPanel", "BriefView", right_brief_view);
                key_file.set_boolean("RightPanel", "ShowHidden", right_show_hidden);

                // Bookmarks
                if (bookmarks != null) {
                    string[] b_names = new string[bookmarks.length];
                    string[] b_paths = new string[bookmarks.length];
                    for (uint i = 0; i < bookmarks.length; i++) {
                        var bm = bookmarks.get(i);
                        b_names[i] = bm.name;
                        b_paths[i] = bm.uri_or_path;
                    }
                    key_file.set_string_list("Bookmarks", "Names", b_names);
                    key_file.set_string_list("Bookmarks", "Paths", b_paths);
                }
                key_file.set_integer("Bookmarks", "DialogWidth", bookmarks_dialog_width);
                key_file.set_integer("Bookmarks", "DialogHeight", bookmarks_dialog_height);

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
