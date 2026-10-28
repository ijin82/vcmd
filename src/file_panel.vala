namespace VCommander {

    public class FilePanel : Gtk.Box {
        public bool is_active { get; private set; default = false; }
        public Adw.TabView tab_view { get; private set; }
        public Adw.TabBar tab_bar { get; private set; }

        public signal void panel_activated(FilePanel panel);
        public signal void error_occurred(string title, string message);
        public signal void directory_changed(File new_dir);
        public signal void command_char_typed(string ch);

        public FilePanel(string[] initial_dirs, int active_index = 0, bool brief = false, bool hidden = false) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            add_css_class("file-panel");

            tab_view = new Adw.TabView();
            tab_bar = new Adw.TabBar();
            tab_bar.view = tab_view;
            tab_bar.autohide = false;

            append(tab_bar);
            append(tab_view);

            tab_view.page_attached.connect(on_tab_page_attached);
            tab_view.close_page.connect(on_tab_close_page);
            tab_view.notify["selected-page"].connect(on_tab_selection_changed);

            // Open initial tabs
            if (initial_dirs.length == 0) {
                var home = File.new_for_path(Environment.get_home_dir());
                open_new_tab(home, brief, hidden);
            } else {
                for (int i = 0; i < initial_dirs.length; i++) {
                    var f = File.new_for_commandline_arg(initial_dirs[i]);
                    if (!f.query_exists()) {
                        f = File.new_for_path(Environment.get_home_dir());
                    }
                    open_new_tab(f, brief, hidden);
                }
            }

            if (active_index >= 0 && active_index < tab_view.n_pages) {
                tab_view.selected_page = tab_view.get_nth_page(active_index);
            }
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

        public bool show_hidden {
            get {
                var page = get_current_page();
                return page != null ? page.show_hidden : false;
            }
        }

        public void open_new_tab(File? dir = null, bool brief = false, bool hidden = false) {
            File target_dir = dir;
            if (target_dir == null) {
                var current = get_current_page();
                if (current != null && current.current_directory != null) {
                    target_dir = current.current_directory;
                    brief = current.is_brief_view;
                    hidden = current.show_hidden;
                } else {
                    target_dir = File.new_for_path(Environment.get_home_dir());
                }
            }

            var page_widget = new FilePanelPage(target_dir, brief, hidden);
            page_widget.hexpand = true;
            page_widget.vexpand = true;

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

            var page = tab_view.append(page_widget);
            update_tab_title(page_widget);
            tab_view.selected_page = page;

            if (is_active) {
                page_widget.set_active(true);
                page_widget.grab_focus_to_list();
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
            tab_view.select_next_page();
            grab_focus_to_list();
        }

        public void select_previous_tab() {
            tab_view.select_previous_page();
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

            entry.activate.connect(() => {
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
                dialog.force_close();
                grab_focus_to_list();
            });

            dialog.choose.begin(parent_window, null, (obj, res) => {
                string response = dialog.choose.end(res);
                if (response == "apply") {
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
            return true;
        }

        private void on_tab_page_attached(Adw.TabPage page, int position) {
            var page_widget = (FilePanelPage) page.child;
            update_tab_title(page_widget);
        }

        private void on_tab_selection_changed() {
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
        }

        private void update_tab_title(FilePanelPage page_widget) {
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
            if (active) {
                add_css_class("active-panel");
            } else {
                remove_css_class("active-panel");
            }
            var page = get_current_page();
            if (page != null) {
                page.set_active(active);
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

        public void refresh() {
            var page = get_current_page();
            if (page != null) {
                page.refresh();
            }
        }

        public void load_directory(File dir) {
            var page = get_current_page();
            if (page != null) {
                page.load_directory(dir);
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

        public int get_active_tab_index() {
            var selected = tab_view.selected_page;
            if (selected == null) return 0;
            return tab_view.get_page_position(selected);
        }
    }
}
