namespace VCommander {

    public class SearchDialog : Object {
        private static SearchDialog? active = null;

        public signal void ready(File root, GenericArray<FileItem> items, string summary);

        private unowned Gtk.Window parent_window;
        private Adw.Dialog dialog;
        private Gtk.Entry path_entry;
        private Gtk.Entry name_entry;
        private Gtk.Entry content_entry;
        private Gtk.Switch case_switch;
        private Gtk.Switch hidden_switch;
        private Gtk.Label status_label;
        private Gtk.Button search_button;
        private Cancellable? cancellable = null;
        private bool running = false;
        private bool closed = false;
        private bool deliver_results = false;
        private File? result_root = null;
        private GenericArray<FileItem>? result_items = null;
        private string result_summary = "";

        public static SearchDialog? show(Gtk.Window parent, File start_dir, bool include_hidden) {
            if (active != null) {
                active.dialog.present(parent);
                return active;
            }
            var dlg = new SearchDialog(parent, start_dir, include_hidden);
            dlg.present();
            return dlg;
        }

        private SearchDialog(Gtk.Window parent, File start_dir, bool include_hidden) {
            this.parent_window = parent;
            active = this;

            dialog = new Adw.Dialog();
            dialog.title = "Find File";
            dialog.content_width = 560;
            dialog.content_height = 420;

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.show_title = true;
            toolbar.add_top_bar(header);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            box.margin_start = 16;
            box.margin_end = 16;
            box.margin_top = 12;
            box.margin_bottom = 12;

            var config = ConfigManager.get_instance();
            path_entry = add_field(box, "Start at", "Directory to search");
            path_entry.text = start_dir.get_parse_name();
            path_entry.secondary_icon_name = "folder-open-symbolic";
            path_entry.secondary_icon_tooltip_text = "Choose folder";
            path_entry.icon_release.connect((pos) => {
                if (pos == Gtk.EntryIconPosition.SECONDARY && !running) {
                    choose_folder();
                }
            });

            name_entry = add_field(box, "File name", "Name or mask (* and ?). A plain word matches anywhere");
            content_entry = add_field(box, "File content", "Text inside files. Directories match by name only");
            if (config.search_has_saved) {
                name_entry.text = config.search_name;
                content_entry.text = config.search_content;
            }

            case_switch = add_switch(box, "Case sensitive", "Match letter case in names and content");
            hidden_switch = add_switch(box, "Search hidden files", "Include names that start with a dot");
            if (config.search_has_saved) {
                case_switch.active = config.search_case_sensitive;
                hidden_switch.active = config.search_include_hidden;
            } else {
                hidden_switch.active = include_hidden;
            }

            status_label = new Gtk.Label("Enter a name, a content string, or both");
            status_label.xalign = 0;
            status_label.wrap = true;
            status_label.add_css_class("dim-label");
            box.append(status_label);

            toolbar.set_content(box);

            var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            bottom.margin_start = 12;
            bottom.margin_end = 12;
            bottom.margin_top = 8;
            bottom.margin_bottom = 8;

            var close_button = new Gtk.Button.with_label("Cancel");
            close_button.clicked.connect(() => {
                dialog.close();
            });
            bottom.append(close_button);

            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom.append(spacer);

            search_button = new Gtk.Button.with_label("Search");
            search_button.add_css_class("suggested-action");
            search_button.clicked.connect(() => {
                if (running) {
                    stop_search();
                } else {
                    start_search.begin();
                }
            });
            bottom.append(search_button);
            toolbar.add_bottom_bar(bottom);
            dialog.set_child(toolbar);

            path_entry.activate.connect(begin_from_entry);
            name_entry.activate.connect(begin_from_entry);
            content_entry.activate.connect(begin_from_entry);

            var key = new Gtk.EventControllerKey();
            key.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    if (running) {
                        stop_search();
                    } else {
                        dialog.close();
                    }
                    return Gdk.EVENT_STOP;
                }
                return Gdk.EVENT_PROPAGATE;
            });
            box.add_controller(key);

            dialog.closed.connect(() => {
                closed = true;
                if (cancellable != null) {
                    cancellable.cancel();
                }
                if (active == this) {
                    active = null;
                }
                if (deliver_results && result_root != null && result_items != null) {
                    ready(result_root, result_items, result_summary);
                }
            });
        }

        private void present() {
            dialog.present(parent_window);
            name_entry.grab_focus();
            name_entry.select_region(0, -1);
        }

        private void begin_from_entry() {
            if (!running) {
                start_search.begin();
            }
        }

        private Gtk.Entry add_field(Gtk.Box box, string title, string hint) {
            var label = new Gtk.Label(title);
            label.xalign = 0;
            box.append(label);

            var entry = new Gtk.Entry();
            entry.hexpand = true;
            entry.placeholder_text = hint;
            entry.tooltip_text = hint;
            box.append(entry);
            return entry;
        }

        private Gtk.Switch add_switch(Gtk.Box box, string title, string hint) {
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            row.margin_top = 4;
            var label = new Gtk.Label(title);
            label.xalign = 0;
            label.hexpand = true;
            label.tooltip_text = hint;
            var sw = new Gtk.Switch();
            sw.valign = Gtk.Align.CENTER;
            sw.tooltip_text = hint;
            row.append(label);
            row.append(sw);
            box.append(row);
            return sw;
        }

        private void choose_folder() {
            var picker = new Gtk.FileDialog();
            picker.title = "Search in Folder";
            string current = path_entry.text.strip();
            if (current.length > 0) {
                picker.initial_folder = File.new_for_commandline_arg(current);
            }
            picker.select_folder.begin(parent_window, null, (obj, res) => {
                try {
                    File? folder = picker.select_folder.end(res);
                    if (folder != null) {
                        path_entry.text = folder.get_parse_name();
                    }
                } catch (Error e) {
                }
            });
        }

        private void set_inputs_sensitive(bool sensitive) {
            path_entry.sensitive = sensitive;
            name_entry.sensitive = sensitive;
            content_entry.sensitive = sensitive;
            case_switch.sensitive = sensitive;
            hidden_switch.sensitive = sensitive;
        }

        private void stop_search() {
            if (cancellable != null) {
                cancellable.cancel();
            }
            status_label.label = "Stopping…";
        }

        private async void start_search() {
            string start = path_entry.text.strip();
            if (start.length == 0) {
                status_label.label = "Choose a start directory";
                return;
            }
            bool name_specified;
            string pattern = FileSearchEngine.normalize_name_pattern(name_entry.text, case_switch.active, out name_specified);
            string content = content_entry.text;
            string needle = case_switch.active ? content : content.down();
            bool content_specified = needle.strip().length > 0;
            if (!name_specified && !content_specified) {
                status_label.label = "Enter a file name or text to find inside files";
                return;
            }

            File root = File.new_for_commandline_arg(start);
            try {
                var info = yield root.query_info_async(
                    "standard::type",
                    FileQueryInfoFlags.NONE,
                    Priority.DEFAULT,
                    null
                );
                if (info.get_file_type() != FileType.DIRECTORY) {
                    status_label.label = "Start path is not a directory";
                    return;
                }
            } catch (Error e) {
                status_label.label = e.message;
                return;
            }

            if (closed) {
                return;
            }

            var config = ConfigManager.get_instance();
            config.search_name = name_entry.text;
            config.search_content = content_entry.text;
            config.search_case_sensitive = case_switch.active;
            config.search_include_hidden = hidden_switch.active;
            config.search_has_saved = true;
            config.save();

            running = true;
            search_button.label = "Stop";
            set_inputs_sensitive(false);
            status_label.label = "Searching…";

            var query = new FileSearchQuery();
            query.root = root;
            query.name_pattern = pattern;
            query.name_specified = name_specified;
            query.content_needle = needle;
            query.content_specified = content_specified;
            query.case_sensitive = case_switch.active;
            query.include_hidden = hidden_switch.active;

            cancellable = new Cancellable();
            var engine = new FileSearchEngine(query);
            engine.progress.connect((path, found, scanned) => {
                if (!closed) {
                    string short_path = path;
                    if (short_path.char_count() > 72) {
                        short_path = "…" + short_path.substring(short_path.length - 68);
                    }
                    status_label.label = @"$found found, $scanned scanned\n$short_path";
                }
            });

            GenericArray<FileItem> items;
            bool cancelled = false;
            try {
                items = yield engine.run(cancellable);
            } catch (IOError.CANCELLED e) {
                items = new GenericArray<FileItem>();
                cancelled = true;
            } catch (Error e) {
                running = false;
                search_button.label = "Search";
                set_inputs_sensitive(true);
                status_label.label = e.message;
                return;
            }

            cancelled = cancelled || (cancellable != null && cancellable.is_cancelled());
            running = false;
            if (closed) {
                return;
            }

            string summary = engine.summary(items.length, cancelled);
            if (items.length == 0) {
                search_button.label = "Search";
                set_inputs_sensitive(true);
                status_label.label = summary;
                return;
            }

            result_root = root;
            result_items = items;
            result_summary = summary;
            deliver_results = true;
            dialog.close();
        }
    }
}
