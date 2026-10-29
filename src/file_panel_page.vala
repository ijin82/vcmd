namespace VCommander {
    public enum PanelViewMode {
        BRIEF = 0,
        DETAILED = 1,
        SUPER = 2;

        public static PanelViewMode parse(string val) {
            if (val == "super" || val == "2") return SUPER;
            if (val == "brief" || val == "0" || val == "true") return BRIEF;
            return DETAILED; // "detailed", "full", "1", "false"
        }

        public string to_string_id() {
            switch (this) {
                case BRIEF: return "brief";
                case DETAILED: return "detailed";
                case SUPER: return "super";
                default: return "detailed";
            }
        }
    }

    public class FilePanelPage : Gtk.Box {
        public File current_directory { get; private set; }
        public bool show_hidden { get; private set; default = false; }
        public PanelViewMode view_mode { get; private set; default = PanelViewMode.DETAILED; }
        public bool is_brief_view { get { return view_mode == PanelViewMode.BRIEF; } }
        public bool is_active { get; private set; default = false; }
        public string? custom_title { get; set; default = null; }

        private ListStore store;
        private Gtk.CustomFilter custom_filter;
        private Gtk.FilterListModel filter_model;
        private Gtk.SortListModel sort_model;
        private Gtk.SingleSelection selection_model;
        private uint saved_selected_pos = Gtk.INVALID_LIST_POSITION;

        // Views
        private Gtk.ColumnView column_view;
        private Gtk.ColumnView super_column_view;
        private Gtk.GridView grid_view;
        private Gtk.ScrolledWindow full_scrolled;
        private Gtk.ScrolledWindow super_scrolled;
        private Gtk.ScrolledWindow brief_scrolled;
        private Gtk.Stack view_stack;
        private Gtk.CustomSorter custom_master_sorter;

        private Gtk.Box header_box;
        private Gtk.Entry path_entry;
        private Gtk.Box filter_box;
        private Gtk.Entry filter_entry;
        private string filter_text = "";
        private string current_dir_stats = "";
        private Gtk.Box status_box;
        private Gtk.Label status_label;
        private Gtk.Button view_toggle_button;
        private Gtk.ToggleButton hidden_toggle;
        private Cancellable? load_cancellable = null;
        private Cancellable? dir_calc_cancellable = null;
        private FileItem? calculating_item = null;

        // Detailed view columns (no Type column)
        private Gtk.ColumnViewColumn name_col;
        private Gtk.ColumnViewColumn size_col;
        private Gtk.ColumnViewColumn time_col;
        private Gtk.ColumnViewColumn dummy_col;

        // Super Detailed view columns (Name, Owner, Group, Permission, Size, Dummy)
        private Gtk.ColumnViewColumn super_name_col;
        private Gtk.ColumnViewColumn super_owner_col;
        private Gtk.ColumnViewColumn super_group_col;
        private Gtk.ColumnViewColumn super_perm_col;
        private Gtk.ColumnViewColumn super_size_col;
        private Gtk.ColumnViewColumn super_dummy_col;

        private bool updating_columns = false;

        public string sort_column_id { get; private set; default = "name"; }
        public string sort_order_str { get; private set; default = "asc"; }
        private bool initializing_sort = true;

        public signal void page_activated();
        public signal void error_occurred(string title, string message);
        public signal void directory_changed(File new_dir);
        public signal void command_char_typed(string ch);
        public signal void columns_layout_changed();
        public signal void sort_changed();
        public signal void view_mode_changed();
        public signal void toggle_hidden_requested();

        public FilePanelPage(File initial_dir, string view_mode_str = "detailed", bool hidden = false, string sort_col = "name", string sort_order = "asc") {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            this.view_mode = PanelViewMode.parse(view_mode_str);
            this.show_hidden = hidden;
            this.sort_column_id = (sort_col == "size" || sort_col == "mtime" || sort_col == "owner" || sort_col == "group" || sort_col == "perm") ? sort_col : "name";
            this.sort_order_str = (sort_order == "desc") ? "desc" : "asc";
            store = new ListStore(typeof(FileItem));

            build_header();
            build_views();
            build_status_bar();
            setup_focus_and_click_handlers();

            load_directory(initial_dir);
            initializing_sort = false;
        }

        private void build_header() {
            var config = ConfigManager.get_instance();
            header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            header_box.add_css_class("panel-header");
            header_box.visible = config.show_path_toolbar;

            var up_button = new Gtk.Button.from_icon_name("go-up-symbolic");
            up_button.focusable = false;
            up_button.tooltip_text = "Go to parent directory (Backspace)";
            up_button.clicked.connect(() => {
                go_up();
            });
            header_box.append(up_button);

            path_entry = new Gtk.Entry();
            path_entry.hexpand = true;
            path_entry.tooltip_text = "Current path (Press Enter to navigate, Ctrl+L to focus)";
            path_entry.activate.connect(() => {
                var entered_path = path_entry.text.strip();
                if (entered_path.length > 0) {
                    File target;
                    if (entered_path.has_prefix("/") || entered_path.contains("://")) {
                        target = File.new_for_commandline_arg(entered_path);
                    } else {
                        target = current_directory.resolve_relative_path(entered_path);
                    }
                    load_directory(target);
                }
                grab_focus_to_list();
            });

            var entry_key_controller = new Gtk.EventControllerKey();
            entry_key_controller.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    if (current_directory != null) {
                        path_entry.text = current_directory.get_parse_name();
                    }
                    grab_focus_to_list();
                    return Gdk.EVENT_STOP;
                }
                return Gdk.EVENT_PROPAGATE;
            });
            path_entry.add_controller(entry_key_controller);

            header_box.append(path_entry);

            // Toggle view button (Alt+T)
            view_toggle_button = new Gtk.Button();
            update_view_toggle_button();
            view_toggle_button.focusable = false;
            view_toggle_button.clicked.connect(() => {
                toggle_view_mode();
            });
            header_box.append(view_toggle_button);

            var refresh_button = new Gtk.Button.from_icon_name("view-refresh-symbolic");
            refresh_button.focusable = false;
            refresh_button.tooltip_text = "Refresh directory";
            refresh_button.clicked.connect(() => {
                refresh();
            });
            header_box.append(refresh_button);

            hidden_toggle = new Gtk.ToggleButton();
            hidden_toggle.focusable = false;
            hidden_toggle.icon_name = "view-more-symbolic";
            hidden_toggle.tooltip_text = "Show hidden files (Ctrl+H)";
            hidden_toggle.active = show_hidden;
            hidden_toggle.toggled.connect(() => {
                if (show_hidden != hidden_toggle.active) {
                    toggle_hidden_requested();
                }
            });
            header_box.append(hidden_toggle);

            append(header_box);
        }

        private void update_brief_item_label(FileItem file_item, Gtk.Label label) {
            if (file_item.is_calculating_size) {
                label.label = file_item.display_name + " [Counting...]";
            } else if (file_item.custom_size >= 0) {
                label.label = file_item.display_name + " (" + format_size(file_item.custom_size) + ")";
            } else {
                label.label = file_item.display_name;
            }
        }

        private void build_views() {
            // 1. ColumnView (Full View)
            column_view = new Gtk.ColumnView(null);
            column_view.add_css_class("file-list-view");
            column_view.reorderable = true;

            var config = ConfigManager.get_instance();

            // Name Column
            var name_factory = new Gtk.SignalListItemFactory();
            name_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                var image = new Gtk.Image();
                image.pixel_size = 20;

                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.hexpand = true;

                box.append(image);
                box.append(label);
                list_item.child = box;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                box.add_controller(right_click);
            });

            name_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var box = (Gtk.Box) list_item.child;
                var image = (Gtk.Image) box.get_first_child();
                var label = (Gtk.Label) image.get_next_sibling();

                image.gicon = file_item.icon;
                label.label = file_item.display_name;

                label.remove_css_class("file-item-parent");
                label.remove_css_class("file-item-dir");
                label.remove_css_class("file-item-symlink");

                if (file_item.is_parent_dir) {
                    label.add_css_class("file-item-parent");
                } else if (file_item.is_symlink) {
                    label.add_css_class("file-item-symlink");
                    if (file_item.is_dir) {
                        label.add_css_class("file-item-dir");
                    }
                } else if (file_item.is_dir) {
                    label.add_css_class("file-item-dir");
                }

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("name_tag_id", tag_handler_id);
            });

            name_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("name_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("name_tag_id", 0);
                }
            });

            name_col = new Gtk.ColumnViewColumn("Name", name_factory);
            name_col.id = "name";
            name_col.expand = true;
            name_col.resizable = true;
            if (config.col_width_name > 50) {
                name_col.fixed_width = config.col_width_name;
            }
            name_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_name((FileItem) a, (FileItem) b);
            });
            name_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            // Size Column
            var size_factory = new Gtk.SignalListItemFactory();
            size_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 1.0f;
                label.hexpand = true;
                list_item.child = label;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                label.add_controller(right_click);
            });

            size_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.formatted_size;

                ulong handler_id = file_item.notify["formatted-size"].connect(() => {
                    label.label = file_item.formatted_size;
                });
                list_item.set_data<ulong>("size_notify_id", handler_id);

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("size_tag_id", tag_handler_id);
            });

            size_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong handler_id = list_item.get_data<ulong>("size_notify_id");
                if (handler_id != 0 && file_item != null) {
                    file_item.disconnect(handler_id);
                    list_item.set_data<ulong>("size_notify_id", 0);
                }
                ulong tag_handler_id = list_item.get_data<ulong>("size_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("size_tag_id", 0);
                }
            });

            size_col = new Gtk.ColumnViewColumn("Size", size_factory);
            size_col.id = "size";
            size_col.fixed_width = config.col_width_size > 30 ? config.col_width_size : 110;
            size_col.resizable = true;
            size_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_size((FileItem) a, (FileItem) b);
            });
            size_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            // Modified Time Column
            var time_factory = new Gtk.SignalListItemFactory();
            time_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.hexpand = true;
                list_item.child = label;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                label.add_controller(right_click);
            });

            time_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.formatted_mtime;

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("time_tag_id", tag_handler_id);
            });

            time_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("time_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("time_tag_id", 0);
                }
            });

            time_col = new Gtk.ColumnViewColumn("Date Modified", time_factory);
            time_col.id = "mtime";
            time_col.fixed_width = config.col_width_mtime > 30 ? config.col_width_mtime : 175;
            time_col.resizable = true;
            time_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_mtime((FileItem) a, (FileItem) b);
            });
            time_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            // Trailing 1px dummy column: allows GTK4 ColumnView to resize the last real column
            var dummy_factory = new Gtk.SignalListItemFactory();
            dummy_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                list_item.child = new Gtk.Label("");
            });
            dummy_col = new Gtk.ColumnViewColumn("", dummy_factory);
            dummy_col.id = "dummy";
            dummy_col.resizable = false;
            dummy_col.fixed_width = 1;

            // Apply configured column order
            apply_columns_order(config.col_order);

            // Connect to column reorder event
            var cols_model = column_view.get_columns();
            cols_model.items_changed.connect(on_column_items_changed);

            // ==========================================================
            // Super Detailed View (Name, Owner, Group, Permission, Size)
            // ==========================================================
            var super_name_factory = new Gtk.SignalListItemFactory();
            super_name_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                var image = new Gtk.Image();
                image.pixel_size = 20;

                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.hexpand = true;

                box.append(image);
                box.append(label);
                list_item.child = box;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                box.add_controller(right_click);
            });

            super_name_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var box = (Gtk.Box) list_item.child;
                var image = (Gtk.Image) box.get_first_child();
                var label = (Gtk.Label) image.get_next_sibling();

                image.gicon = file_item.icon;
                label.label = file_item.display_name;

                label.remove_css_class("file-item-parent");
                label.remove_css_class("file-item-dir");
                label.remove_css_class("file-item-symlink");

                if (file_item.is_parent_dir) {
                    label.add_css_class("file-item-parent");
                } else if (file_item.is_symlink) {
                    label.add_css_class("file-item-symlink");
                    if (file_item.is_dir) {
                        label.add_css_class("file-item-dir");
                    }
                } else if (file_item.is_dir) {
                    label.add_css_class("file-item-dir");
                }

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("s_name_tag_id", tag_handler_id);
            });

            super_name_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("s_name_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("s_name_tag_id", 0);
                }
            });

            super_name_col = new Gtk.ColumnViewColumn("Name", super_name_factory);
            super_name_col.id = "name";
            super_name_col.expand = true;
            super_name_col.resizable = true;
            if (config.super_col_width_name > 50) {
                super_name_col.fixed_width = config.super_col_width_name;
            }
            super_name_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_name((FileItem) a, (FileItem) b);
            });
            super_name_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            var super_owner_factory = new Gtk.SignalListItemFactory();
            super_owner_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.hexpand = true;
                list_item.child = label;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                label.add_controller(right_click);
            });
            super_owner_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.owner;

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("s_owner_tag_id", tag_handler_id);
            });
            super_owner_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("s_owner_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("s_owner_tag_id", 0);
                }
            });
            super_owner_col = new Gtk.ColumnViewColumn("Owner", super_owner_factory);
            super_owner_col.id = "owner";
            super_owner_col.fixed_width = config.super_col_width_owner > 20 ? config.super_col_width_owner : 80;
            super_owner_col.resizable = true;
            super_owner_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_owner((FileItem) a, (FileItem) b);
            });
            super_owner_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            var super_group_factory = new Gtk.SignalListItemFactory();
            super_group_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.hexpand = true;
                list_item.child = label;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                label.add_controller(right_click);
            });
            super_group_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.group;

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("s_group_tag_id", tag_handler_id);
            });
            super_group_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("s_group_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("s_group_tag_id", 0);
                }
            });
            super_group_col = new Gtk.ColumnViewColumn("Group", super_group_factory);
            super_group_col.id = "group";
            super_group_col.fixed_width = config.super_col_width_group > 20 ? config.super_col_width_group : 80;
            super_group_col.resizable = true;
            super_group_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_group((FileItem) a, (FileItem) b);
            });
            super_group_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            var super_perm_factory = new Gtk.SignalListItemFactory();
            super_perm_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.hexpand = true;
                list_item.child = label;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                label.add_controller(right_click);
            });
            super_perm_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.formatted_permissions;

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("s_perm_tag_id", tag_handler_id);
            });
            super_perm_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("s_perm_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("s_perm_tag_id", 0);
                }
            });
            super_perm_col = new Gtk.ColumnViewColumn("Permission", super_perm_factory);
            super_perm_col.id = "perm";
            super_perm_col.fixed_width = config.super_col_width_perm > 20 ? config.super_col_width_perm : 110;
            super_perm_col.resizable = true;
            super_perm_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_permissions((FileItem) a, (FileItem) b);
            });
            super_perm_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            var super_size_factory = new Gtk.SignalListItemFactory();
            super_size_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 1.0f;
                label.hexpand = true;
                list_item.child = label;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                label.add_controller(right_click);
            });
            super_size_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.formatted_size;

                ulong handler_id = file_item.notify["formatted-size"].connect(() => {
                    label.label = file_item.formatted_size;
                });
                list_item.set_data<ulong>("s_size_notify_id", handler_id);

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("s_size_tag_id", tag_handler_id);
            });
            super_size_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong handler_id = list_item.get_data<ulong>("s_size_notify_id");
                if (handler_id != 0 && file_item != null) {
                    file_item.disconnect(handler_id);
                    list_item.set_data<ulong>("s_size_notify_id", 0);
                }
                ulong tag_handler_id = list_item.get_data<ulong>("s_size_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("s_size_tag_id", 0);
                }
            });
            super_size_col = new Gtk.ColumnViewColumn("Size", super_size_factory);
            super_size_col.id = "size";
            super_size_col.fixed_width = config.super_col_width_size > 20 ? config.super_col_width_size : 100;
            super_size_col.resizable = true;
            super_size_col.sorter = new Gtk.CustomSorter((a, b) => {
                return FileItem.compare_by_size((FileItem) a, (FileItem) b);
            });
            super_size_col.notify["fixed-width"].connect(() => {
                on_column_width_changed();
            });

            var super_dummy_factory = new Gtk.SignalListItemFactory();
            super_dummy_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                list_item.child = new Gtk.Label("");
            });
            super_dummy_col = new Gtk.ColumnViewColumn("", super_dummy_factory);
            super_dummy_col.id = "dummy";
            super_dummy_col.resizable = false;
            super_dummy_col.fixed_width = 1;

            super_column_view = new Gtk.ColumnView(null);
            super_column_view.add_css_class("file-list-view");
            super_column_view.reorderable = true;
            super_column_view.append_column(super_name_col);
            super_column_view.append_column(super_owner_col);
            super_column_view.append_column(super_group_col);
            super_column_view.append_column(super_perm_col);
            super_column_view.append_column(super_size_col);
            super_column_view.append_column(super_dummy_col);

            // Apply initial sort column and direction
            Gtk.ColumnViewColumn target_col = name_col;
            if (sort_column_id == "size") {
                target_col = size_col;
            } else if (sort_column_id == "mtime") {
                target_col = time_col;
            }
            Gtk.SortType target_dir = (sort_order_str == "desc") ? Gtk.SortType.DESCENDING : Gtk.SortType.ASCENDING;
            column_view.sort_by_column(target_col, target_dir);

            Gtk.ColumnViewColumn super_target_col = super_name_col;
            if (sort_column_id == "size") {
                super_target_col = super_size_col;
            } else if (sort_column_id == "owner") {
                super_target_col = super_owner_col;
            } else if (sort_column_id == "group") {
                super_target_col = super_group_col;
            } else if (sort_column_id == "perm") {
                super_target_col = super_perm_col;
            }
            super_column_view.sort_by_column(super_target_col, target_dir);

            // Master sorter ensuring parent directory '..' is ALWAYS first,
            // and directories are ALWAYS before files, regardless of column sorting or direction.
            var cv_sorter = column_view.sorter;
            var super_cv_sorter = super_column_view.sorter;

            custom_master_sorter = new Gtk.CustomSorter((a, b) => {
                var fa = (FileItem) a;
                var fb = (FileItem) b;
                if (fa.is_parent_dir && !fb.is_parent_dir) return -1;
                if (!fa.is_parent_dir && fb.is_parent_dir) return 1;
                if (fa.is_parent_dir && fb.is_parent_dir) return 0;

                // Directories always first
                if (fa.is_dir && !fb.is_dir) return -1;
                if (!fa.is_dir && fb.is_dir) return 1;

                Gtk.Sorter current_sorter = (view_mode == PanelViewMode.SUPER) ? (Gtk.Sorter) super_column_view.sorter : (Gtk.Sorter) column_view.sorter;
                var res = current_sorter.compare((GLib.Object) a, (GLib.Object) b);
                if (res == Gtk.Ordering.SMALLER) return -1;
                if (res == Gtk.Ordering.LARGER) return 1;
                return 0;
            });

            cv_sorter.changed.connect(() => {
                var cv_s = column_view.sorter as Gtk.ColumnViewSorter;
                if (cv_s != null) {
                    var pcol = cv_s.get_primary_sort_column();
                    if (pcol != null && pcol.id != null && pcol.id.length > 0) {
                        sort_column_id = pcol.id;
                        sort_order_str = (cv_s.get_primary_sort_order() == Gtk.SortType.DESCENDING) ? "desc" : "asc";
                    }
                }
                custom_master_sorter.changed(Gtk.SorterChange.DIFFERENT);
                if (!initializing_sort) {
                    sort_changed();
                }
            });

            super_cv_sorter.changed.connect(() => {
                var cv_s = super_column_view.sorter as Gtk.ColumnViewSorter;
                if (cv_s != null) {
                    var pcol = cv_s.get_primary_sort_column();
                    if (pcol != null && pcol.id != null && pcol.id.length > 0) {
                        sort_column_id = pcol.id;
                        sort_order_str = (cv_s.get_primary_sort_order() == Gtk.SortType.DESCENDING) ? "desc" : "asc";
                    }
                }
                custom_master_sorter.changed(Gtk.SorterChange.DIFFERENT);
                if (!initializing_sort) {
                    sort_changed();
                }
            });

            // Custom filter for quick substring matching (case-insensitive)
            custom_filter = new Gtk.CustomFilter((item) => {
                var file_item = (FileItem) item;
                if (file_item.is_parent_dir) {
                    return true;
                }
                if (filter_text.length == 0) {
                    return true;
                }
                return file_item.name.down().contains(filter_text);
            });
            filter_model = new Gtk.FilterListModel(store, custom_filter);

            // Shared sort model and selection
            sort_model = new Gtk.SortListModel(filter_model, custom_master_sorter);
            selection_model = new Gtk.SingleSelection(sort_model);
            selection_model.autoselect = false;
            selection_model.can_unselect = true;

            selection_model.notify["selected"].connect(() => {
                if (selection_model.selected != Gtk.INVALID_LIST_POSITION) {
                    saved_selected_pos = selection_model.selected;
                }
            });

            column_view.model = selection_model;
            column_view.activate.connect(on_item_activated);
            attach_view_controllers(column_view);

            super_column_view.model = selection_model;
            super_column_view.activate.connect(on_item_activated);
            attach_view_controllers(super_column_view);

            // 2. GridView (Brief View)
            grid_view = new Gtk.GridView(selection_model, create_brief_factory());
            grid_view.orientation = Gtk.Orientation.HORIZONTAL;
            grid_view.max_columns = 100;
            grid_view.min_columns = 1;
            grid_view.add_css_class("file-list-view");
            grid_view.activate.connect(on_item_activated);
            attach_view_controllers(grid_view);

            // 3. Quick Filter Bar (Ctrl+S)
            build_filter_bar();

            // 4. Stack to switch between Detailed, Brief and Super Detailed view
            view_stack = new Gtk.Stack();
            view_stack.hexpand = true;
            view_stack.vexpand = true;
            view_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            view_stack.transition_duration = 100;

            full_scrolled = new Gtk.ScrolledWindow();
            full_scrolled.hexpand = true;
            full_scrolled.vexpand = true;
            full_scrolled.child = column_view;
            view_stack.add_named(full_scrolled, "full");

            brief_scrolled = new Gtk.ScrolledWindow();
            brief_scrolled.hexpand = true;
            brief_scrolled.vexpand = true;
            brief_scrolled.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            brief_scrolled.vscrollbar_policy = Gtk.PolicyType.NEVER;
            brief_scrolled.child = grid_view;
            view_stack.add_named(brief_scrolled, "brief");

            super_scrolled = new Gtk.ScrolledWindow();
            super_scrolled.hexpand = true;
            super_scrolled.vexpand = true;
            super_scrolled.child = super_column_view;
            view_stack.add_named(super_scrolled, "super");

            view_stack.visible_child_name = (view_mode == PanelViewMode.DETAILED) ? "full" : view_mode.to_string_id();
            append(view_stack);
        }

        private void build_filter_bar() {
            filter_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            filter_box.add_css_class("filter-box");
            filter_box.visible = false;

            var filter_icon = new Gtk.Image.from_icon_name("system-search-symbolic");
            filter_icon.pixel_size = 16;
            filter_box.append(filter_icon);

            filter_entry = new Gtk.Entry();
            filter_entry.hexpand = true;
            filter_entry.max_length = 20;
            filter_entry.placeholder_text = "Quick filter (max 20 chars)...";
            filter_entry.secondary_icon_name = "edit-clear-symbolic";
            filter_entry.secondary_icon_tooltip_text = "Clear and close filter (Esc)";
            filter_entry.icon_release.connect((pos) => {
                if (pos == Gtk.EntryIconPosition.SECONDARY) {
                    hide_filter();
                }
            });

            filter_entry.changed.connect(() => {
                filter_text = filter_entry.text.strip().down();
                custom_filter.changed(Gtk.FilterChange.DIFFERENT);

                uint matched = sort_model.get_n_items();
                if (filter_text.length > 0) {
                    // Update status bar with match count
                    uint actual_matches = (matched > 0 && ((FileItem) sort_model.get_item(0)).is_parent_dir) ? matched - 1 : matched;
                    status_label.label = @"Filter: '$filter_text' | Matched: $actual_matches items";
                    if (matched > 1) {
                        selection_model.selected = 1;
                    } else if (matched > 0) {
                        selection_model.selected = 0;
                    }
                    scroll_to_selected();
                } else if (filter_box.visible) {
                    status_label.label = current_dir_stats;
                    if (matched > 0) {
                        selection_model.selected = 0;
                        scroll_to_selected();
                    }
                }
            });

            filter_entry.activate.connect(() => {
                uint pos = selection_model.selected;
                if (pos != Gtk.INVALID_LIST_POSITION) {
                    on_item_activated(pos);
                }
            });

            var key_ctrl = new Gtk.EventControllerKey();
            key_ctrl.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key_ctrl.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    hide_filter();
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.ISO_Enter) {
                    uint pos = selection_model.selected;
                    if (pos != Gtk.INVALID_LIST_POSITION) {
                        on_item_activated(pos);
                    }
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Down) {
                    uint cur = selection_model.selected;
                    uint total = sort_model.get_n_items();
                    if (total > 0 && cur + 1 < total) {
                        selection_model.selected = cur + 1;
                        scroll_to_selected();
                    }
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Up) {
                    uint cur = selection_model.selected;
                    if (cur > 0) {
                        selection_model.selected = cur - 1;
                        scroll_to_selected();
                    }
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Page_Down) {
                    uint cur = selection_model.selected;
                    uint total = sort_model.get_n_items();
                    if (total > 0) {
                        uint next = uint.min(cur + 10, total - 1);
                        selection_model.selected = next;
                        scroll_to_selected();
                    }
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Page_Up) {
                    uint cur = selection_model.selected;
                    if (cur > 0) {
                        uint next = (cur > 10) ? cur - 10 : 0;
                        selection_model.selected = next;
                        scroll_to_selected();
                    }
                    return Gdk.EVENT_STOP;
                }
                return Gdk.EVENT_PROPAGATE;
            });
            filter_entry.add_controller(key_ctrl);

            filter_box.append(filter_entry);
            append(filter_box);
        }

        private void attach_view_controllers(Gtk.Widget target_view) {
            var key_controller = new Gtk.EventControllerKey();
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                uint latin_key = KeyUtils.to_latin(keyval, keycode);

                if (keyval == Gdk.Key.Escape && is_filter_active) {
                    hide_filter();
                    return Gdk.EVENT_STOP;
                }

                // Insert / KP_Insert: Toggle tag on current item and advance cursor down
                if (keyval == Gdk.Key.Insert || keyval == Gdk.Key.KP_Insert) {
                    toggle_tag_current_item();
                    return Gdk.EVENT_STOP;
                }

                if (keyval == Gdk.Key.BackSpace) {
                    go_up();
                    return Gdk.EVENT_STOP;
                }
                if (latin_key == Gdk.Key.h && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    toggle_hidden_requested();
                    return Gdk.EVENT_STOP;
                }
                if (latin_key == Gdk.Key.l && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    path_entry.grab_focus();
                    path_entry.select_region(0, -1);
                    return Gdk.EVENT_STOP;
                }
                if ((latin_key == Gdk.Key.r || keyval == Gdk.Key.r || keyval == Gdk.Key.R) &&
                    (state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    refresh();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Space: calculate folder or file size
                if (keyval == Gdk.Key.space && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    calculate_selected_size();
                    return Gdk.EVENT_STOP;
                }

                // Alt+T: toggle Brief / Full view mode
                if (latin_key == Gdk.Key.t && (state & Gdk.ModifierType.ALT_MASK) != 0) {
                    toggle_view_mode();
                    return Gdk.EVENT_STOP;
                }

                // Alt+Up: Go to parent directory
                if (keyval == Gdk.Key.Up && (state & Gdk.ModifierType.ALT_MASK) != 0) {
                    go_up();
                    return Gdk.EVENT_STOP;
                }

                // Left Arrow: Jump to top/first item (Full view or leftmost column in Brief view)
                if (keyval == Gdk.Key.Left && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (handle_left_arrow()) {
                        return Gdk.EVENT_STOP;
                    }
                    return Gdk.EVENT_PROPAGATE;
                }

                // Right Arrow: Jump to end/last item (Full view or rightmost column in Brief view)
                if (keyval == Gdk.Key.Right && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    if (handle_right_arrow()) {
                        return Gdk.EVENT_STOP;
                    }
                    return Gdk.EVENT_PROPAGATE;
                }

                // If user types a printable character (without Ctrl/Alt), route to terminal command line
                if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK)) == 0) {
                    if (keyval >= Gdk.Key.F1 && keyval <= Gdk.Key.F35) {
                        return Gdk.EVENT_PROPAGATE;
                    }
                    unichar c = Gdk.keyval_to_unicode(keyval);
                    if (c != 0 && c.isprint() && c != ' ') {
                        command_char_typed(c.to_string());
                        return Gdk.EVENT_STOP;
                    }
                }

                return Gdk.EVENT_PROPAGATE;
            });
            target_view.add_controller(key_controller);

            var focus_controller = new Gtk.EventControllerFocus();
            focus_controller.enter.connect(() => {
                page_activated();
            });
            target_view.add_controller(focus_controller);
        }

        private void build_status_bar() {
            status_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            status_box.add_css_class("panel-status-bar");

            status_label = new Gtk.Label("Loading...");
            status_label.xalign = 0.0f;
            status_label.yalign = 0.5f;
            status_label.ellipsize = Pango.EllipsizeMode.END;
            status_label.hexpand = true;
            status_box.append(status_label);

            append(status_box);
        }

        private void setup_focus_and_click_handlers() {
            var click_gesture = new Gtk.GestureClick();
            click_gesture.pressed.connect(() => {
                page_activated();
                if (!path_entry.has_focus) {
                    grab_focus_to_list();
                }
            });
            add_controller(click_gesture);
        }

        public void toggle_view_mode() {
            if (view_mode == PanelViewMode.BRIEF) {
                switch_view_mode(PanelViewMode.DETAILED);
            } else if (view_mode == PanelViewMode.DETAILED) {
                switch_view_mode(PanelViewMode.SUPER);
            } else {
                switch_view_mode(PanelViewMode.BRIEF);
            }
        }

        public void switch_view_mode(PanelViewMode mode) {
            view_mode = mode;
            view_stack.visible_child_name = (view_mode == PanelViewMode.DETAILED) ? "full" : view_mode.to_string_id();
            update_view_toggle_button();
            if (custom_master_sorter != null) {
                custom_master_sorter.changed(Gtk.SorterChange.DIFFERENT);
            }
            grab_focus_to_list();
            scroll_to_selected();
            view_mode_changed();
        }

        private void update_view_toggle_button() {
            if (view_toggle_button == null) return;
            switch (view_mode) {
                case PanelViewMode.BRIEF:
                    view_toggle_button.icon_name = "view-list-bullet-symbolic";
                    view_toggle_button.tooltip_text = "Switch to Detailed View (Alt+T)";
                    break;
                case PanelViewMode.DETAILED:
                    view_toggle_button.icon_name = "view-list-details-symbolic";
                    view_toggle_button.tooltip_text = "Switch to Super Detailed View (Alt+T)";
                    break;
                case PanelViewMode.SUPER:
                    view_toggle_button.icon_name = "view-list-compact-symbolic";
                    view_toggle_button.tooltip_text = "Switch to Brief View (Alt+T)";
                    break;
            }
        }

        public void calculate_selected_size() {
            var item = get_selected_item();
            if (item == null || item.is_parent_dir) {
                return;
            }

            if (!item.is_dir) {
                string msg = @"File: '$(item.display_name)' | Size: $(format_size(item.size)) ($(item.size) bytes)";
                status_label.label = msg;
                return;
            }

            // If a directory calculation is already in progress
            if (calculating_item != null) {
                if (calculating_item == item) {
                    if (dir_calc_cancellable != null) {
                        dir_calc_cancellable.cancel();
                    }
                    calculating_item.is_calculating_size = false;
                    calculating_item.notify_property("formatted-size");
                    calculating_item = null;
                    status_label.label = @"Size calculation cancelled for '$(item.display_name)'";
                    return;
                } else {
                    status_label.label = @"Counting size for '$(calculating_item.display_name)'... Please wait or cancel first.";
                    return;
                }
            }

            start_calculate_dir_size(item);
        }

        private void start_calculate_dir_size(FileItem item) {
            dir_calc_cancellable = new Cancellable();
            var cancellable = dir_calc_cancellable;

            calculating_item = item;
            item.is_calculating_size = true;
            item.notify_property("formatted-size");

            string dir_name = item.display_name;
            var dir_file = item.file;
            status_label.label = @"Counting size [$(dir_name)]... (Ctrl+Space to cancel)";

            new Thread<void*>("dir-calc", () => {
                int64 total_bytes = 0;
                int64 total_files = 0;

                calc_recursive(dir_file, ref total_bytes, ref total_files, cancellable);

                Idle.add(() => {
                    item.is_calculating_size = false;
                    if (calculating_item == item) {
                        calculating_item = null;
                    }
                    if (!cancellable.is_cancelled()) {
                        item.custom_size = total_bytes;
                        status_label.label = @"Directory '$dir_name': $(format_size(total_bytes)) ($total_files items)";
                    }
                    item.notify_property("formatted-size");
                    return false;
                });
                return null;
            });
        }

        private void calc_recursive(File dir, ref int64 total_bytes, ref int64 total_files, Cancellable cancellable) {
            if (cancellable.is_cancelled()) return;
            try {
                var enumerator = dir.enumerate_children(
                    "standard::name,standard::type,standard::size",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    cancellable
                );
                while (!cancellable.is_cancelled()) {
                    FileInfo? info = enumerator.next_file(cancellable);
                    if (info == null) {
                        break;
                    }
                    if (info.get_file_type() == FileType.DIRECTORY) {
                        var sub = dir.get_child(info.get_name());
                        calc_recursive(sub, ref total_bytes, ref total_files, cancellable);
                    } else {
                        total_bytes += info.get_size();
                        total_files++;
                    }
                }
            } catch (Error e) {
                // Ignore permission or unreadable folders
            }
        }

        private Gtk.SignalListItemFactory create_brief_factory() {
            var config = ConfigManager.get_instance();
            var brief_factory = new Gtk.SignalListItemFactory();
            brief_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
                box.add_css_class("brief-item-box");
                box.width_request = config.brief_column_width;

                var image = new Gtk.Image();
                image.pixel_size = 18;

                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.hexpand = true;

                box.append(image);
                box.append(label);
                list_item.child = box;

                var right_click = new Gtk.GestureClick();
                right_click.button = 3;
                right_click.pressed.connect(() => {
                    on_item_right_clicked(list_item);
                });
                box.add_controller(right_click);
            });

            brief_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var box = (Gtk.Box) list_item.child;
                box.width_request = config.brief_column_width;
                var image = (Gtk.Image) box.get_first_child();
                var label = (Gtk.Label) image.get_next_sibling();

                image.gicon = file_item.icon;

                update_brief_item_label(file_item, label);

                ulong handler_id = file_item.notify["formatted-size"].connect(() => {
                    update_brief_item_label(file_item, label);
                });
                list_item.set_data<ulong>("brief_notify_id", handler_id);

                label.remove_css_class("file-item-parent");
                label.remove_css_class("file-item-dir");
                label.remove_css_class("file-item-symlink");

                if (file_item.is_parent_dir) {
                    label.add_css_class("file-item-parent");
                } else if (file_item.is_symlink) {
                    label.add_css_class("file-item-symlink");
                    if (file_item.is_dir) {
                        label.add_css_class("file-item-dir");
                    }
                } else if (file_item.is_dir) {
                    label.add_css_class("file-item-dir");
                }

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("brief_tag_id", tag_handler_id);
            });

            brief_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong handler_id = list_item.get_data<ulong>("brief_notify_id");
                if (handler_id != 0 && file_item != null) {
                    file_item.disconnect(handler_id);
                    list_item.set_data<ulong>("brief_notify_id", 0);
                }
                ulong tag_handler_id = list_item.get_data<ulong>("brief_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("brief_tag_id", 0);
                }
            });

            return brief_factory;
        }

        public void update_brief_column_width() {
            grid_view.factory = create_brief_factory();
        }

        public void set_path_toolbar_visible(bool visible) {
            header_box.visible = visible;
        }

        public void set_active(bool active) {
            is_active = active;
            if (active) {
                add_css_class("active-page");
                remove_css_class("inactive-page");
                if (selection_model.selected != Gtk.INVALID_LIST_POSITION) {
                    saved_selected_pos = selection_model.selected;
                    scroll_to_selected();
                } else if (saved_selected_pos != Gtk.INVALID_LIST_POSITION && saved_selected_pos < sort_model.get_n_items()) {
                    selection_model.selected = saved_selected_pos;
                    scroll_to_selected();
                } else if (sort_model.get_n_items() > 0 && selection_model.selected == Gtk.INVALID_LIST_POSITION) {
                    selection_model.selected = (sort_model.get_n_items() > 1 && ((FileItem) sort_model.get_item(0)).is_parent_dir) ? 1 : 0;
                    scroll_to_selected();
                }
            } else {
                remove_css_class("active-page");
                add_css_class("inactive-page");
                if (selection_model.selected != Gtk.INVALID_LIST_POSITION) {
                    saved_selected_pos = selection_model.selected;
                    selection_model.selected = Gtk.INVALID_LIST_POSITION;
                }
            }
        }

        public bool is_filter_active {
            get {
                return filter_box != null && (filter_box.visible || filter_text.length > 0);
            }
        }

        public void show_filter() {
            if (filter_box == null) return;
            filter_box.visible = true;
            filter_entry.grab_focus();
            filter_entry.select_region(0, -1);
        }

        public void hide_filter() {
            if (filter_box == null) return;
            filter_box.visible = false;
            filter_entry.text = "";
            filter_text = "";
            custom_filter.changed(Gtk.FilterChange.DIFFERENT);
            if (current_dir_stats.length > 0) {
                update_status_bar();
            }
            grab_focus_to_list();
        }

        public void grab_focus_to_list() {
            if (view_mode == PanelViewMode.BRIEF) {
                grid_view.grab_focus();
            } else if (view_mode == PanelViewMode.SUPER) {
                super_column_view.grab_focus();
            } else {
                column_view.grab_focus();
            }
        }

        public void select_first_item() {
            uint n = sort_model.get_n_items();
            if (n > 0) {
                selection_model.selected = 0;
                scroll_to_selected();
                // Ensure scrolled window adjustment resets to 0 (top/start) like Home key
                if (view_mode == PanelViewMode.BRIEF && brief_scrolled != null) {
                    var hadj = brief_scrolled.get_hadjustment();
                    if (hadj != null) hadj.set_value(hadj.get_lower());
                } else if (view_mode == PanelViewMode.SUPER && super_scrolled != null) {
                    var vadj = super_scrolled.get_vadjustment();
                    if (vadj != null) vadj.set_value(vadj.get_lower());
                } else if (full_scrolled != null) {
                    var vadj = full_scrolled.get_vadjustment();
                    if (vadj != null) vadj.set_value(vadj.get_lower());
                }
            }
        }

        public void select_last_item() {
            uint n = sort_model.get_n_items();
            if (n > 0) {
                selection_model.selected = n - 1;
                scroll_to_selected();
                // Ensure scrolled window adjustment scrolls to bottom/end like End key
                if (view_mode == PanelViewMode.BRIEF && brief_scrolled != null) {
                    var hadj = brief_scrolled.get_hadjustment();
                    if (hadj != null) hadj.set_value(hadj.get_upper() - hadj.get_page_size());
                } else if (view_mode == PanelViewMode.SUPER && super_scrolled != null) {
                    var vadj = super_scrolled.get_vadjustment();
                    if (vadj != null) vadj.set_value(vadj.get_upper() - vadj.get_page_size());
                } else if (full_scrolled != null) {
                    var vadj = full_scrolled.get_vadjustment();
                    if (vadj != null) vadj.set_value(vadj.get_upper() - vadj.get_page_size());
                }
            }
        }

        private void scroll_to_selected() {
            uint pos = selection_model.selected;
            if (pos == Gtk.INVALID_LIST_POSITION) return;

            if (view_mode == PanelViewMode.BRIEF) {
                grid_view.scroll_to(pos, Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT, null);
            } else if (view_mode == PanelViewMode.SUPER) {
                super_column_view.scroll_to(pos, null, Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT, null);
            } else {
                column_view.scroll_to(pos, null, Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT, null);
            }
        }

        private uint get_brief_rows_per_col() {
            uint rows = 0;
            var child = grid_view.get_first_child();
            while (child != null) {
                Graphene.Rect bounds;
                if (child.compute_bounds(grid_view, out bounds)) {
                    if (bounds.get_x() > 1.0f) {
                        break;
                    }
                }
                rows++;
                child = child.get_next_sibling();
            }
            return rows > 0 ? rows : 1;
        }

        public bool handle_left_arrow() {
            uint n = sort_model.get_n_items();
            if (n == 0) return false;

            if (!is_brief_view) {
                // In Full view, Left arrow jumps to top of folder (first item)
                select_first_item();
                return true;
            } else {
                // In Brief view: if currently in the leftmost column, jump to first item
                uint cur_pos = selection_model.selected;
                if (cur_pos == Gtk.INVALID_LIST_POSITION) {
                    select_first_item();
                    return true;
                }
                uint rows = get_brief_rows_per_col();
                if (cur_pos < rows) {
                    // Leftmost column
                    select_first_item();
                    return true;
                }
                return false; // let Gtk.GridView move one column to the left
            }
        }

        public bool handle_right_arrow() {
            uint n = sort_model.get_n_items();
            if (n == 0) return false;

            if (!is_brief_view) {
                // In Full view, Right arrow jumps to end of folder (last item)
                select_last_item();
                return true;
            } else {
                // In Brief view: if currently in the rightmost column, jump to last item
                uint cur_pos = selection_model.selected;
                if (cur_pos == Gtk.INVALID_LIST_POSITION) {
                    select_last_item();
                    return true;
                }
                uint rows = get_brief_rows_per_col();
                uint col_index = cur_pos / rows;
                uint last_col_index = (n - 1) / rows;
                if (col_index >= last_col_index) {
                    // Rightmost column
                    select_last_item();
                    return true;
                }
                return false; // let Gtk.GridView move one column to the right
            }
        }

        public FileItem? get_selected_item() {
            uint pos = selection_model.selected;
            if (pos == Gtk.INVALID_LIST_POSITION) {
                pos = saved_selected_pos;
            }
            if (pos == Gtk.INVALID_LIST_POSITION || pos >= sort_model.get_n_items()) {
                return null;
            }
            return (FileItem) sort_model.get_item(pos);
        }

        public string? get_item_above_selection_or_first_tag() {
            uint total = sort_model.get_n_items();
            if (total == 0) return null;

            // 1. Check if there are tagged items; find the first (minimum index) tagged item
            uint first_del_pos = Gtk.INVALID_LIST_POSITION;
            for (uint i = 0; i < total; i++) {
                var it = (FileItem) sort_model.get_item(i);
                if (it != null && it.is_tagged && !it.is_parent_dir) {
                    first_del_pos = i;
                    break;
                }
            }

            // 2. If no tagged items, use the currently selected item position
            if (first_del_pos == Gtk.INVALID_LIST_POSITION) {
                uint sel = selection_model.selected;
                if (sel == Gtk.INVALID_LIST_POSITION) {
                    sel = saved_selected_pos;
                }
                if (sel != Gtk.INVALID_LIST_POSITION && sel < total) {
                    first_del_pos = sel;
                }
            }

            if (first_del_pos != Gtk.INVALID_LIST_POSITION && first_del_pos > 0) {
                var above_item = (FileItem) sort_model.get_item(first_del_pos - 1);
                if (above_item != null) {
                    return above_item.name;
                }
            }

            return null;
        }
        public void apply_columns_order(string[] order) {
            updating_columns = true;
            var cols_model = column_view.get_columns();
            while (cols_model.get_n_items() > 0) {
                column_view.remove_column((Gtk.ColumnViewColumn) cols_model.get_item(0));
            }

            foreach (var col_id in order) {
                if (col_id == "name" && name_col != null) {
                    column_view.append_column(name_col);
                } else if (col_id == "size" && size_col != null) {
                    column_view.append_column(size_col);
                } else if (col_id == "mtime" && time_col != null) {
                    column_view.append_column(time_col);
                }
            }

            // Ensure any omitted column is added
            if (!column_has_been_added("name") && name_col != null) column_view.append_column(name_col);
            if (!column_has_been_added("size") && size_col != null) column_view.append_column(size_col);
            if (!column_has_been_added("mtime") && time_col != null) column_view.append_column(time_col);

            // Dummy column is always at the end
            if (dummy_col != null) {
                column_view.append_column(dummy_col);
            }
            updating_columns = false;
        }

        private bool column_has_been_added(string col_id) {
            var cols_model = column_view.get_columns();
            uint n = cols_model.get_n_items();
            for (uint i = 0; i < n; i++) {
                var c = (Gtk.ColumnViewColumn) cols_model.get_item(i);
                if (c.id == col_id) return true;
            }
            return false;
        }

        private void on_column_items_changed(uint pos, uint removed, uint added) {
            if (updating_columns) return;
            var cols_model = column_view.get_columns();
            uint n = cols_model.get_n_items();
            if (n == 0) return;

            // Ensure dummy_col stays at the very end
            var last_col = (Gtk.ColumnViewColumn) cols_model.get_item(n - 1);
            if (dummy_col != null && last_col != dummy_col) {
                updating_columns = true;
                column_view.remove_column(dummy_col);
                column_view.append_column(dummy_col);
                updating_columns = false;
            }

            save_columns_to_config();
            columns_layout_changed();
        }

        private void on_column_width_changed() {
            if (updating_columns) return;
            save_columns_to_config();
            columns_layout_changed();
        }

        public void save_columns_to_config() {
            var config = ConfigManager.get_instance();
            var cols_model = column_view.get_columns();
            uint n = cols_model.get_n_items();
            var order = new GenericArray<string>();

            for (uint i = 0; i < n; i++) {
                var col = (Gtk.ColumnViewColumn) cols_model.get_item(i);
                string cid = col.id;
                if (cid != null && cid.length > 0 && cid != "dummy") {
                    order.add(cid);
                }
            }

            var order_arr = new string[order.length];
            for (int i = 0; i < order.length; i++) {
                order_arr[i] = order[i];
            }
            config.col_order = order_arr;

            // Detailed view columns
            if (name_col.fixed_width > 30) config.col_width_name = name_col.fixed_width;
            if (size_col.fixed_width > 30) config.col_width_size = size_col.fixed_width;
            if (time_col.fixed_width > 30) config.col_width_mtime = time_col.fixed_width;

            // Super Detailed view columns
            if (super_name_col.fixed_width > 30) config.super_col_width_name = super_name_col.fixed_width;
            if (super_owner_col.fixed_width > 20) config.super_col_width_owner = super_owner_col.fixed_width;
            if (super_group_col.fixed_width > 20) config.super_col_width_group = super_group_col.fixed_width;
            if (super_perm_col.fixed_width > 20) config.super_col_width_perm = super_perm_col.fixed_width;
            if (super_size_col.fixed_width > 20) config.super_col_width_size = super_size_col.fixed_width;
        }

        public void update_columns_layout() {
            var config = ConfigManager.get_instance();
            updating_columns = true;

            apply_columns_order(config.col_order);

            // Detailed view
            if (config.col_width_name > 30) name_col.fixed_width = config.col_width_name;
            if (config.col_width_size > 30) size_col.fixed_width = config.col_width_size;
            if (config.col_width_mtime > 30) time_col.fixed_width = config.col_width_mtime;

            // Super Detailed view
            if (config.super_col_width_name > 30) super_name_col.fixed_width = config.super_col_width_name;
            if (config.super_col_width_owner > 20) super_owner_col.fixed_width = config.super_col_width_owner;
            if (config.super_col_width_group > 20) super_group_col.fixed_width = config.super_col_width_group;
            if (config.super_col_width_perm > 20) super_perm_col.fixed_width = config.super_col_width_perm;
            if (config.super_col_width_size > 20) super_size_col.fixed_width = config.super_col_width_size;

            updating_columns = false;
        }
        private void apply_tag_class(Gtk.Widget widget, bool is_tagged) {
            if (is_tagged) {
                widget.add_css_class("file-item-tagged");
            } else {
                widget.remove_css_class("file-item-tagged");
            }
        }

        private void on_item_right_clicked(Gtk.ListItem list_item) {
            page_activated();
            grab_focus_to_list();

            var file_item = (FileItem) list_item.item;
            if (file_item == null || file_item.is_parent_dir) {
                return;
            }

            file_item.is_tagged = !file_item.is_tagged;
            update_status_bar();
        }

        public void toggle_tag_current_item() {
            uint pos = selection_model.selected;
            if (pos == Gtk.INVALID_LIST_POSITION) {
                pos = saved_selected_pos;
            }
            uint total = sort_model.get_n_items();
            if (pos != Gtk.INVALID_LIST_POSITION && pos < total) {
                var item = (FileItem) sort_model.get_item(pos);
                if (item != null && !item.is_parent_dir) {
                    item.is_tagged = !item.is_tagged;
                    update_status_bar();
                }
                // Advance cursor to next item
                if (pos + 1 < total) {
                    selection_model.selected = pos + 1;
                }
            }
        }

        public GenericArray<FileItem> get_tagged_items() {
            var list = new GenericArray<FileItem>();
            uint n = sort_model.get_n_items();
            for (uint i = 0; i < n; i++) {
                var item = (FileItem) sort_model.get_item(i);
                if (item != null && item.is_tagged && !item.is_parent_dir) {
                    list.add(item);
                }
            }
            return list;
        }

        public void clear_tags() {
            uint n = sort_model.get_n_items();
            for (uint i = 0; i < n; i++) {
                var item = (FileItem) sort_model.get_item(i);
                if (item != null && item.is_tagged) {
                    item.is_tagged = false;
                }
            }
            update_status_bar();
        }

        public void select_by_mask(string pattern, bool include_dirs) {
            if (pattern.length == 0) return;

            var spec = new PatternSpec(pattern);
            uint n = sort_model.get_n_items();
            for (uint i = 0; i < n; i++) {
                var item = (FileItem) sort_model.get_item(i);
                if (item == null || item.is_parent_dir) {
                    continue;
                }

                if (item.is_dir && !include_dirs) {
                    continue;
                }

                if (spec.match_string(item.display_name)) {
                    item.is_tagged = true;
                }
            }
            update_status_bar();
        }

        public void update_status_bar() {
            if (is_filter_active && filter_entry.text.length > 0) {
                return;
            }

            uint tagged_count = 0;
            int64 tagged_bytes = 0;
            uint n = sort_model.get_n_items();
            for (uint i = 0; i < n; i++) {
                var item = (FileItem) sort_model.get_item(i);
                if (item != null && item.is_tagged && !item.is_parent_dir) {
                    tagged_count++;
                    if (!item.is_dir) {
                        tagged_bytes += item.size;
                    } else if (item.custom_size >= 0) {
                        tagged_bytes += item.custom_size;
                    }
                }
            }

            if (tagged_count > 0) {
                status_label.label = @"$current_dir_stats | Selected: $tagged_count ($(format_size(tagged_bytes)))";
            } else {
                status_label.label = current_dir_stats;
            }
        }

        private void on_item_activated(uint position) {
            var item = (FileItem) sort_model.get_item(position);
            if (item == null) {
                return;
            }

            if (item.is_parent_dir) {
                go_up();
            } else if (item.is_dir) {
                load_directory(item.file);
            } else {
                open_file_with_default_app(item);
            }
        }

        public void go_up() {
            var parent = current_directory.get_parent();
            if (parent != null) {
                string prev_folder_name = current_directory.get_basename();
                load_directory(parent, prev_folder_name);
            }
        }

        public void apply_show_hidden(bool hidden) {
            if (this.show_hidden != hidden) {
                this.show_hidden = hidden;
                if (hidden_toggle != null && hidden_toggle.active != hidden) {
                    hidden_toggle.active = hidden;
                }
                refresh();
            }
        }

        public void refresh() {
            if (current_directory != null) {
                load_directory(current_directory);
            }
        }

        public void open_file_with_default_app(FileItem item) {
            // Determine content type
            string? content_type = null;
            try {
                var info = item.file.query_info(
                    FileAttribute.STANDARD_CONTENT_TYPE + "," + FileAttribute.STANDARD_FAST_CONTENT_TYPE,
                    FileQueryInfoFlags.NONE,
                    null
                );
                content_type = info.get_content_type();
            } catch (Error e) {
                // Ignore
            }

            if (content_type == null || content_type == "application/octet-stream") {
                bool uncertain = false;
                content_type = ContentType.guess(item.display_name, null, out uncertain);
            }

            if (content_type == null || content_type.length == 0) {
                content_type = "application/octet-stream";
            }

            AppInfo? default_app = AppInfo.get_default_for_type(content_type, false);
            if (default_app != null) {
                try {
                    var files = new GLib.List<File>();
                    files.append(item.file);
                    default_app.launch(files, null);
                    return;
                } catch (Error e) {
                    warning("Failed to launch default app %s for %s: %s", default_app.get_display_name(), item.name, e.message);
                }
            }

            // Fallback: If no default app exists or launching failed, open the "Open With..." dialog
            open_file_with_dialog(item);
        }

        public void open_file_with_dialog(FileItem item) {
            var root_window = get_root() as Gtk.Window;
            if (root_window != null) {
                OpenWithDialog.show(root_window, item.file, item.display_name);
            }
        }

        public void load_directory(File dir, string? target_select_name = null) {
            hide_filter();

            if (load_cancellable != null) {
                load_cancellable.cancel();
            }
            load_cancellable = new Cancellable();

            if (dir_calc_cancellable != null) {
                dir_calc_cancellable.cancel();
            }
            calculating_item = null;

            // When reloading the same directory, preserve tagged items and cursor item
            GenericSet<string>? preserved_tags = null;
            string? cursor_select_name = target_select_name;
            if (current_directory != null && current_directory.equal(dir)) {
                preserved_tags = new GenericSet<string>(str_hash, str_equal);
                uint n = sort_model.get_n_items();
                for (uint i = 0; i < n; i++) {
                    var it = (FileItem) sort_model.get_item(i);
                    if (it != null && it.is_tagged && !it.is_parent_dir) {
                        preserved_tags.add(it.name);
                    }
                }
                if (cursor_select_name == null) {
                    var cur_selected = get_selected_item();
                    if (cur_selected != null && !cur_selected.is_parent_dir) {
                        cursor_select_name = cur_selected.name;
                    }
                }
            }

            current_directory = dir;
            path_entry.text = dir.get_parse_name();
            directory_changed(dir);

            load_directory_async.begin(dir, cursor_select_name, preserved_tags, load_cancellable);
        }

        private async void load_directory_async(File dir, string? target_select_name, GenericSet<string>? preserved_tags, Cancellable cancellable) {
            status_label.label = "Scanning directory...";

            var items = new GenericArray<FileItem>();

            var parent = dir.get_parent();
            if (parent != null) {
                items.add(new FileItem.for_parent(parent));
            }

            uint count_files = 0;
            uint count_dirs = 0;
            int64 total_bytes = 0;

            try {
                var enumerator = yield dir.enumerate_children_async(
                    "standard::name,standard::display-name,standard::type,standard::size,standard::is-hidden,standard::is-symlink,standard::icon,time::modified,owner::user,owner::group,unix::uid,unix::user-name,unix::gid,unix::group-name,unix::mode",
                    FileQueryInfoFlags.NONE,
                    Priority.DEFAULT,
                    cancellable
                );

                while (true) {
                    var files = yield enumerator.next_files_async(50, Priority.DEFAULT, cancellable);
                    if (files == null || files.length() == 0) {
                        break;
                    }

                    foreach (var info in files) {
                        string name = info.get_name();
                        bool is_hidden = info.get_is_hidden() || name.has_prefix(".");

                        if (is_hidden && !show_hidden) {
                            continue;
                        }

                        var child_file = dir.get_child(name);
                        var item = new FileItem(child_file, info);
                        if (preserved_tags != null && preserved_tags.contains(name)) {
                            item.is_tagged = true;
                        }
                        items.add(item);

                        if (item.is_dir) {
                            count_dirs++;
                        } else {
                            count_files++;
                            total_bytes += item.size;
                        }
                    }
                }
            } catch (IOError.CANCELLED e) {
                return;
            } catch (Error e) {
                error_occurred("Directory Error", @"Cannot read directory $(dir.get_parse_name()): $(e.message)");
                status_label.label = @"Error: $(e.message)";
                return;
            }

            var array = new Object[items.length];
            for (int i = 0; i < items.length; i++) {
                array[i] = items[i];
            }
            store.splice(0, store.get_n_items(), array);

            string free_space_str = "";
            try {
                var fs_info = yield dir.query_filesystem_info_async("filesystem::free", Priority.DEFAULT, cancellable);
                uint64 free_space = fs_info.get_attribute_uint64("filesystem::free");
                free_space_str = @" | Free: $(format_size((int64)free_space))";
            } catch (Error e) {
            }

            current_dir_stats = @"$(count_dirs) folders, $(count_files) files ($(format_size(total_bytes)))$(free_space_str)";
            update_status_bar();

            uint total_items = sort_model.get_n_items();
            if (total_items > 0) {
                uint target_index = 0;
                bool found_target = false;

                if (target_select_name != null && target_select_name.length > 0) {
                    for (uint i = 0; i < total_items; i++) {
                        var file_item = (FileItem) sort_model.get_item(i);
                        if (file_item != null && !file_item.is_parent_dir && file_item.name == target_select_name) {
                            target_index = i;
                            found_target = true;
                            break;
                        }
                    }
                }

                // If not returning to a specific folder, select index 0 (the ".." parent directory or first item)
                if (!found_target) {
                    target_index = 0;
                }

                if (is_active) {
                    selection_model.selected = target_index;
                    scroll_to_selected();
                    grab_focus_to_list();
                } else {
                    saved_selected_pos = target_index;
                    selection_model.selected = Gtk.INVALID_LIST_POSITION;
                }
            }
        }
    }
}
