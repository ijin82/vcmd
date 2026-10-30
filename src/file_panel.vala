namespace VCommander {

    public class FilePanel : Gtk.Box {
        public bool is_active { get; private set; default = false; }
        public Adw.TabView tab_view { get; private set; }
        public Adw.TabBar tab_bar { get; private set; }
        private bool initializing = true;

        public signal void panel_activated(FilePanel panel);
        public signal void error_occurred(string title, string message);
        public signal void directory_changed(File new_dir);
        public signal void command_char_typed(string ch);
        public signal void columns_layout_changed(FilePanel origin_panel);
        public signal void tab_sort_changed(FilePanel panel);
        public signal void tabs_state_changed(FilePanel panel);
        public signal void view_mode_changed(FilePanel panel);
        public signal void toggle_hidden_requested();

        public FilePanel(string[] initial_dirs, string[]? initial_titles = null, int active_index = 0, bool brief = false, bool hidden = false, string[]? sort_cols = null, string[]? sort_orders = null, string[]? view_modes = null) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            add_css_class("file-panel");

            tab_view = new Adw.TabView();
            tab_view.shortcuts = Adw.TabViewShortcuts.NONE;
            tab_bar = new Adw.TabBar();
            tab_bar.view = tab_view;
            tab_bar.autohide = false;

            var bar_click = new Gtk.GestureClick();
            bar_click.pressed.connect(() => {
                if (!is_active) {
                    panel_activated(this);
                }
            });
            tab_bar.add_controller(bar_click);

            append(tab_bar);
            append(tab_view);

            tab_view.page_attached.connect(on_tab_page_attached);
            tab_view.close_page.connect(on_tab_close_page);
            tab_view.page_reordered.connect((p, pos) => {
                if (!initializing) {
                    tabs_state_changed(this);
                }
            });
            tab_view.notify["selected-page"].connect(on_tab_selection_changed);

            // Open initial tabs:
            // 1. If path does not exist, do not open tab.
            // 2. If all paths do not exist (or no paths), open home directory.
            for (int i = 0; i < initial_dirs.length; i++) {
                var f = File.new_for_commandline_arg(initial_dirs[i]);
                if (f.query_exists()) {
                    string? title = null;
                    if (initial_titles != null && i < initial_titles.length && initial_titles[i].length > 0) {
                        title = initial_titles[i];
                    }
                    string scol = "name";
                    if (sort_cols != null && i < sort_cols.length && sort_cols[i] != null && sort_cols[i].length > 0) {
                        scol = sort_cols[i];
                    }
                    string sord = "asc";
                    if (sort_orders != null && i < sort_orders.length && sort_orders[i] != null && sort_orders[i].length > 0) {
                        sord = sort_orders[i];
                    }
                    string vmode = brief ? "brief" : "detailed";
                    if (view_modes != null && i < view_modes.length && view_modes[i] != null && view_modes[i].length > 0) {
                        vmode = view_modes[i];
                    }
                    open_new_tab(f, vmode, hidden, title, scol, sord);
                }
            }

            if (tab_view.n_pages == 0) {
                var home = File.new_for_path(Environment.get_home_dir());
                string fallback_vmode = brief ? "brief" : "detailed";
                if (view_modes != null && view_modes.length > 0 && view_modes[0] != null && view_modes[0].length > 0) {
                    fallback_vmode = view_modes[0];
                }
                open_new_tab(home, fallback_vmode, hidden, null, "name", "asc");
            }

            if (active_index >= 0 && active_index < tab_view.n_pages) {
                tab_view.selected_page = tab_view.get_nth_page(active_index);
            } else if (tab_view.n_pages > 0) {
                tab_view.selected_page = tab_view.get_nth_page(0);
            }
            initializing = false;
        }

        public FilePanelPage? get_current_page() {
            var selected = tab_view.selected_page;
            if (selected == null) {
                return null;
            }
            return (FilePanelPage) selected.child;
        }

        public File? current_directory {
            get {
                var page = get_current_page();
                return page != null ? page.current_directory : null;
            }
        }

        public bool is_brief_view {
            get {
                var page = get_current_page();
                return page != null ? page.is_brief_view : false;
            }
        }

        public bool is_super_view {
            get {
                var page = get_current_page();
                return page != null ? (page.view_mode == PanelViewMode.SUPER) : false;
            }
        }

        public PanelViewMode view_mode {
            get {
                var page = get_current_page();
                return page != null ? page.view_mode : PanelViewMode.DETAILED;
            }
        }

        public bool show_hidden {
            get {
                var page = get_current_page();
                return page != null ? page.show_hidden : false;
            }
        }

        public bool is_filter_active {
            get {
                var page = get_current_page();
                return page != null ? page.is_filter_active : false;
            }
        }

        public void show_filter() {
            var page = get_current_page();
            if (page != null) {
                page.show_filter();
            }
        }

        public void hide_filter() {
            var page = get_current_page();
            if (page != null) {
                page.hide_filter();
            }
        }

        public FileItem? get_selected_item() {
            var page = get_current_page();
            return page != null ? page.get_selected_item() : null;
        }

        public void open_selected_with_dialog() {
            var page = get_current_page();
            if (page != null) {
                var item = page.get_selected_item();
                if (item != null && !item.is_dir && !item.is_parent_dir) {
                    page.open_file_with_dialog(item);
                }
            }
        }

        public string? get_item_above_selection_or_first_tag() {
            var page = get_current_page();
            return page != null ? page.get_item_above_selection_or_first_tag() : null;
        }

        public GenericArray<FileItem> get_tagged_items() {
            var page = get_current_page();
            return page != null ? page.get_tagged_items() : new GenericArray<FileItem>();
        }

        public void clear_tags() {
            var page = get_current_page();
            if (page != null) {
                page.clear_tags();
            }
        }

        public void toggle_tag_current_item() {
            var page = get_current_page();
            if (page != null) {
                page.toggle_tag_current_item();
            }
        }

        public void select_by_mask(string pattern, bool include_dirs) {
            var page = get_current_page();
            if (page != null) {
                page.select_by_mask(pattern, include_dirs);
            }
        }

        public void open_new_tab(File? dir = null, string view_mode_str = "detailed", bool hidden = false, string? custom_title = null, string sort_col = "name", string sort_order = "asc", bool defer_load = false) {
            File target_dir = dir;
            string vmode = view_mode_str;
            if (target_dir == null) {
                var current = get_current_page();
                if (current != null && current.current_directory != null) {
                    target_dir = current.current_directory;
                    vmode = current.view_mode.to_string_id();
                } else {
                    target_dir = File.new_for_path(Environment.get_home_dir());
                }
            }
            hidden = ConfigManager.get_instance().show_hidden;

            var page_widget = new FilePanelPage(target_dir, vmode, hidden, sort_col, sort_order, !defer_load);
            page_widget.hexpand = true;
            page_widget.vexpand = true;
            if (custom_title != null && custom_title.length > 0) {
                page_widget.custom_title = custom_title;
            }

            // Wire signals
            page_widget.page_activated.connect(() => {
                panel_activated(this);
            });
            page_widget.error_occurred.connect((title, msg) => {
                error_occurred(title, msg);
            });
            page_widget.directory_changed.connect((d) => {
                update_tab_title(page_widget);
                if (get_current_page() == page_widget) {
                    directory_changed(d);
                }
            });
            page_widget.command_char_typed.connect((ch) => {
                command_char_typed(ch);
            });
            page_widget.columns_layout_changed.connect(() => {
                columns_layout_changed(this);
            });
            page_widget.sort_changed.connect(() => {
                tab_sort_changed(this);
            });
            page_widget.view_mode_changed.connect(() => {
                tabs_state_changed(this);
                view_mode_changed(this);
            });
            page_widget.toggle_hidden_requested.connect(() => {
                toggle_hidden_requested();
            });

            var page = tab_view.append(page_widget);
            update_tab_title(page_widget);
            tab_view.selected_page = page;

            if (is_active) {
                page_widget.set_active(true);
                page_widget.grab_focus_to_list();
            }

            if (!initializing) {
                tabs_state_changed(this);
            }
        }

        public void close_current_tab() {
            if (tab_view.n_pages <= 1) {
                // Protect last remaining tab from closing
                return;
            }
            var page = tab_view.selected_page;
            if (page != null) {
                tab_view.close_page(page);
            }
        }

        public void select_next_tab() {
            if (tab_view.n_pages <= 1) return;
            var cur = tab_view.selected_page;
            int cur_idx = cur != null ? tab_view.get_page_position(cur) : 0;
            int next_idx = (cur_idx + 1) % tab_view.n_pages;
            tab_view.selected_page = tab_view.get_nth_page(next_idx);
            grab_focus_to_list();
        }

        public void select_previous_tab() {
            if (tab_view.n_pages <= 1) return;
            var cur = tab_view.selected_page;
            int cur_idx = cur != null ? tab_view.get_page_position(cur) : 0;
            int prev_idx = (cur_idx - 1 + tab_view.n_pages) % tab_view.n_pages;
            tab_view.selected_page = tab_view.get_nth_page(prev_idx);
            grab_focus_to_list();
        }

        public void prompt_rename_current_tab(Gtk.Window parent_window) {
            var selected_page = tab_view.selected_page;
            if (selected_page == null) return;

            var page_widget = (FilePanelPage) selected_page.child;

            var dialog = new Adw.AlertDialog("Rename Tab", "Enter new name for the current tab (max 15 characters):");
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("apply", "Apply");
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_default_response("apply");
            dialog.set_close_response("cancel");

            var entry = new Gtk.Entry();
            entry.max_length = 15;
            entry.placeholder_text = "Tab title (max 15 chars)";
            entry.text = (page_widget.custom_title != null) ? page_widget.custom_title : selected_page.title;
            entry.margin_start = 12;
            entry.margin_end = 12;
            entry.margin_top = 8;
            entry.margin_bottom = 8;

            dialog.set_extra_child(entry);
            dialog.set_focus(entry);

            bool action_executed = false;

            entry.activate.connect(() => {
                if (action_executed) return;
                action_executed = true;
                string new_name = entry.text.strip();
                if (new_name.char_count() > 15) {
                    new_name = new_name.substring(0, 15);
                }
                if (new_name.length > 0) {
                    page_widget.custom_title = new_name;
                } else {
                    page_widget.custom_title = null;
                }
                update_tab_title(page_widget);
                if (!initializing) {
                    tabs_state_changed(this);
                }
                dialog.force_close();
                grab_focus_to_list();
            });

            dialog.choose.begin(parent_window, null, (obj, res) => {
                string response = dialog.choose.end(res);
                if (action_executed) return;
                if (response == "apply") {
                    action_executed = true;
                    string new_name = entry.text.strip();
                    if (new_name.char_count() > 15) {
                        new_name = new_name.substring(0, 15);
                    }
                    if (new_name.length > 0) {
                        page_widget.custom_title = new_name;
                    } else {
                        page_widget.custom_title = null;
                    }
                    update_tab_title(page_widget);
                    if (!initializing) {
                        tabs_state_changed(this);
                    }
                }
                grab_focus_to_list();
            });

            GLib.Idle.add(() => {
                entry.grab_focus();
                entry.select_region(0, -1);
                return GLib.Source.REMOVE;
            });
        }

        private bool on_tab_close_page(Adw.TabPage page) {
            if (tab_view.n_pages <= 1) {
                return true; // prevent closing last tab
            }
            tab_view.close_page_finish(page, true);
            grab_focus_to_list();
            if (!initializing) {
                tabs_state_changed(this);
            }
            return true;
        }

        private void on_tab_page_attached(Adw.TabPage page, int position) {
            var page_widget = (FilePanelPage) page.child;
            update_tab_title(page_widget);
        }

        private void on_tab_selection_changed() {
            if (!initializing && !is_active) {
                panel_activated(this);
            }
            var current = get_current_page();
            if (current != null) {
                current.set_active(is_active);
                if (current.current_directory != null) {
                    directory_changed(current.current_directory);
                }
                if (is_active) {
                    current.grab_focus_to_list();
                }
            }
            if (!initializing) {
                view_mode_changed(this);
            }
        }

        public void update_tab_title(FilePanelPage page_widget) {
            var page = tab_view.get_page(page_widget);
            if (page == null) return;

            if (page_widget.custom_title != null && page_widget.custom_title.length > 0) {
                string title = page_widget.custom_title;
                if (title.char_count() > 15) {
                    title = title.substring(0, 15);
                }
                page.title = title;
                if (page_widget.current_directory != null) {
                    page.tooltip = page_widget.current_directory.get_parse_name();
                }
                page.icon = new ThemedIcon("folder-symbolic");
            } else if (page_widget.current_directory != null) {
                string name = page_widget.current_directory.get_basename();
                if (name == null || name.length == 0) {
                    name = "/";
                }
                if (name.char_count() > 15) {
                    name = name.substring(0, 15);
                }
                page.title = name;
                page.tooltip = page_widget.current_directory.get_parse_name();
                page.icon = new ThemedIcon("folder-symbolic");
            } else {
                page.title = "Tab";
            }
        }

        public void set_active(bool active) {
            is_active = active;
            tab_view.shortcuts = active ? Adw.TabViewShortcuts.ALL_SHORTCUTS : Adw.TabViewShortcuts.NONE;
            if (active) {
                add_css_class("active-panel");
                remove_css_class("panel-inactive");
            } else {
                remove_css_class("active-panel");
                add_css_class("panel-inactive");
            }
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                pw.set_active(active);
            }
        }

        public void grab_focus_to_list() {
            var page = get_current_page();
            if (page != null) {
                page.grab_focus_to_list();
            }
        }

        public void toggle_view_mode() {
            var page = get_current_page();
            if (page != null) {
                page.toggle_view_mode();
            }
        }

        public void calculate_selected_size() {
            var page = get_current_page();
            if (page != null) {
                page.calculate_selected_size();
            }
        }

        public bool handle_left_arrow() {
            var page = get_current_page();
            if (page != null) {
                return page.handle_left_arrow();
            }
            return false;
        }

        public bool handle_right_arrow() {
            var page = get_current_page();
            if (page != null) {
                return page.handle_right_arrow();
            }
            return false;
        }

        public void go_up() {
            var page = get_current_page();
            if (page != null) {
                page.go_up();
            }
        }

        public bool is_showing_search_results() {
            var page = get_current_page();
            return page != null && page.is_showing_search_results;
        }

        public void refresh() {
            var page = get_current_page();
            if (page != null) {
                page.refresh();
            }
        }

        public void load_directory(File dir, string? target_select_name = null) {
            var page = get_current_page();
            if (page != null) {
                page.load_directory(dir, target_select_name);
            }
        }

        public void set_show_hidden(bool hidden) {
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                pw.apply_show_hidden(hidden);
            }
        }

        public void set_path_toolbar_visible(bool visible) {
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                pw.set_path_toolbar_visible(visible);
            }
        }

        public void update_brief_column_width() {
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                pw.update_brief_column_width();
            }
        }

        public void update_columns_layout(FilePanelPage? exclude_page = null) {
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                if (pw != exclude_page) {
                    pw.update_columns_layout();
                }
            }
        }

        public void save_columns_to_config() {
            var page = get_current_page();
            if (page != null) {
                page.save_columns_to_config();
            }
        }

        public string[] get_tab_paths() {
            var paths = new GenericArray<string>();
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                if (pw.current_directory != null) {
                    paths.add(pw.current_directory.get_parse_name());
                } else {
                    paths.add(Environment.get_home_dir());
                }
            }
            var result = new string[paths.length];
            for (int i = 0; i < paths.length; i++) {
                result[i] = paths[i];
            }
            return result;
        }

        public string[] get_tab_titles() {
            var titles = new GenericArray<string>();
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                titles.add(pw.custom_title != null ? pw.custom_title : "");
            }
            var result = new string[titles.length];
            for (int i = 0; i < titles.length; i++) {
                result[i] = titles[i];
            }
            return result;
        }

        public string[] get_tab_sort_cols() {
            var cols = new GenericArray<string>();
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                cols.add(pw.sort_column_id);
            }
            var result = new string[cols.length];
            for (int i = 0; i < cols.length; i++) {
                result[i] = cols[i];
            }
            return result;
        }

        public string[] get_tab_sort_orders() {
            var orders = new GenericArray<string>();
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                orders.add(pw.sort_order_str);
            }
            var result = new string[orders.length];
            for (int i = 0; i < orders.length; i++) {
                result[i] = orders[i];
            }
            return result;
        }

        public string[] get_tab_view_modes() {
            var modes = new GenericArray<string>();
            for (int i = 0; i < tab_view.n_pages; i++) {
                var p = tab_view.get_nth_page(i);
                var pw = (FilePanelPage) p.child;
                modes.add(pw.view_mode.to_string_id());
            }
            var result = new string[modes.length];
            for (int i = 0; i < modes.length; i++) {
                result[i] = modes[i];
            }
            return result;
        }

        public int get_active_tab_index() {
            var selected = tab_view.selected_page;
            if (selected == null) return 0;
            return tab_view.get_page_position(selected);
        }
    }
}
