namespace VCommander {
    public enum PanelViewMode {
        BRIEF = 0,
        DETAILED = 1,
        SUPER = 2,
        GRID = 3;

        public static PanelViewMode parse(string val) {
            if (val == "grid" || val == "thumbnails" || val == "3") return GRID;
            if (val == "super" || val == "2") return SUPER;
            if (val == "brief" || val == "0" || val == "true") return BRIEF;
            return DETAILED; // "detailed", "full", "1", "false"
        }

        public string to_string_id() {
            switch (this) {
                case BRIEF: return "brief";
                case DETAILED: return "detailed";
                case SUPER: return "super";
                case GRID: return "grid";
                default: return "detailed";
            }
        }
    }

    public class FilePanelPage : Gtk.Box {
        public File current_directory { get; private set; }
        public bool show_hidden { get; private set; default = false; }
        public PanelViewMode view_mode { get; private set; default = PanelViewMode.DETAILED; }
        public bool is_brief_view { get { return view_mode == PanelViewMode.BRIEF; } }
        public bool is_grid_view { get { return view_mode == PanelViewMode.GRID; } }
        public bool is_active { get; private set; default = false; }
        public string? custom_title { get; set; default = null; }
        public bool is_pinned { get; set; default = false; }

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
        private Gtk.GridView thumbnail_grid_view;
        private Gtk.ScrolledWindow full_scrolled;
        private Gtk.ScrolledWindow super_scrolled;
        private Gtk.ScrolledWindow brief_scrolled;
        private Gtk.ScrolledWindow thumbnail_scrolled;
        private Gtk.Stack view_stack;
        private Gtk.CustomSorter custom_master_sorter;

        private Gtk.Box filter_box;
        private Gtk.Entry filter_entry;
        private string filter_text = "";
        private string current_dir_stats = "";
        private Gtk.Box status_box;
        private Gtk.Label status_label;
        private Cancellable? load_cancellable = null;
        private Cancellable? dir_calc_cancellable = null;
        private FileItem? calculating_item = null;
        private uint shift_anchor_pos = Gtk.INVALID_LIST_POSITION;
        private bool is_shift_navigating = false;

        // Detailed view columns (no Type column)
        private Gtk.ColumnViewColumn name_col;
        private Gtk.ColumnViewColumn size_col;
        private Gtk.ColumnViewColumn time_col;
        private Gtk.ColumnViewColumn dummy_col;

        // Trash columns for Detailed View
        private Gtk.ColumnViewColumn trash_orig_col;
        private Gtk.ColumnViewColumn trash_date_col;
        private bool currently_in_trash_columns = false;

        // Contextual Trash Action Banner
        private Gtk.Revealer trash_banner_revealer;
        private Gtk.Box trash_banner_box;
        private Gtk.Label trash_banner_label;
        private Gtk.Button trash_empty_btn;
        private Gtk.Button trash_restore_btn;

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
        private bool showing_search_results = false;
        public bool is_showing_search_results { get { return showing_search_results; } }

        public signal void page_activated();
        public signal void error_occurred(string title, string message);
        public signal void directory_changed(File new_dir);
        public signal void command_char_typed(string ch);
        public signal void columns_layout_changed();
        public signal void sort_changed();
        public signal void view_mode_changed();
        public signal void toggle_hidden_requested();
        public signal void restore_requested();
        public signal void empty_trash_requested();
        public signal void restore_item_requested(FileItem item);

        public bool is_trash_location() {
            return current_directory != null && current_directory.get_uri_scheme() == "trash";
        }

        public bool is_archive_location() {
            return current_directory != null && current_directory.get_uri_scheme() == "archive";
        }

        public FilePanelPage(File initial_dir, string view_mode_str = "detailed", bool hidden = false, string sort_col = "name", string sort_order = "asc", bool start_load = true) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            this.view_mode = PanelViewMode.parse(view_mode_str);
            this.show_hidden = hidden;
            this.sort_column_id = (sort_col == "size" || sort_col == "mtime" || sort_col == "owner" || sort_col == "group" || sort_col == "perm") ? sort_col : "name";
            this.sort_order_str = (sort_order == "desc") ? "desc" : "asc";
            store = new ListStore(typeof(FileItem));

            build_views();
            build_trash_banner();
            build_status_bar();
            setup_focus_and_click_handlers();

            if (start_load) {
                load_directory(initial_dir);
            } else {
                current_directory = initial_dir;
            }
            initializing_sort = false;
        }

        public void present_search_results(File root, GenericArray<FileItem> items, string summary) {
            if (load_cancellable != null) {
                load_cancellable.cancel();
                load_cancellable = null;
            }
            showing_search_results = true;
            current_directory = root;
            if (custom_title == null || custom_title.length == 0) {
                custom_title = "Search";
            }

            var array = new Object[items.length + 1];
            array[0] = new FileItem.for_parent(root);
            for (int i = 0; i < items.length; i++) {
                array[i + 1] = items[i];
            }
            uint old_search_count = store.get_n_items();
            for (uint i = 0; i < old_search_count; i++) {
                var old_item = (FileItem) store.get_item(i);
                if (old_item != null) {
                    old_item.thumbnail_paintable = null;
                    if (old_item.is_thumbnail_requested) {
                        ThumbnailService.cancel_request(old_item);
                    }
                }
            }
            store.splice(0, old_search_count, array);
            ThumbnailService.malloc_trim(0);

            if (view_mode != PanelViewMode.SUPER) {
                switch_view_mode(PanelViewMode.SUPER);
            }
            current_dir_stats = summary;
            update_status_bar();
            directory_changed(root);

            uint cursor = sort_model.get_n_items() > 1 ? 1 : 0;
            if (sort_model.get_n_items() > 0) {
                selection_model.selected = cursor;
                scroll_to_selected();
            }
            focus_search_cursor();
        }

        private void focus_search_cursor() {
            grab_focus_to_list();
            Idle.add(() => {
                if (!showing_search_results) {
                    return Source.REMOVE;
                }
                uint cursor = sort_model.get_n_items() > 1 ? 1 : 0;
                if (sort_model.get_n_items() > 0) {
                    selection_model.selected = cursor;
                    scroll_to_selected();
                }
                grab_focus_to_list();
                return Source.REMOVE;
            });
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

                attach_item_click_controllers(list_item, box);
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

                attach_item_click_controllers(list_item, label);
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

                attach_item_click_controllers(list_item, label);
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

            // Trash Original Path Column
            var trash_orig_factory = new Gtk.SignalListItemFactory();
            trash_orig_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.ellipsize = Pango.EllipsizeMode.START;
                label.hexpand = true;
                list_item.child = label;

                attach_item_click_controllers(list_item, label);
            });

            trash_orig_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.trash_orig_path ?? "";
                label.tooltip_text = file_item.trash_orig_path;

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("trash_orig_tag_id", tag_handler_id);
            });

            trash_orig_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("trash_orig_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("trash_orig_tag_id", 0);
                }
            });

            trash_orig_col = new Gtk.ColumnViewColumn("Original Path", trash_orig_factory);
            trash_orig_col.id = "trash_orig";
            trash_orig_col.expand = true;
            trash_orig_col.resizable = true;
            trash_orig_col.fixed_width = 250;
            trash_orig_col.sorter = new Gtk.CustomSorter((a, b) => {
                var item_a = (FileItem) a;
                var item_b = (FileItem) b;
                if (item_a.is_parent_dir) return -1;
                if (item_b.is_parent_dir) return 1;
                return (item_a.trash_orig_path ?? "").collate(item_b.trash_orig_path ?? "");
            });

            // Trash Date Deleted Column
            var trash_date_factory = new Gtk.SignalListItemFactory();
            trash_date_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var label = new Gtk.Label("");
                label.xalign = 0.0f;
                label.hexpand = true;
                list_item.child = label;

                attach_item_click_controllers(list_item, label);
            });

            trash_date_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var label = (Gtk.Label) list_item.child;
                label.label = file_item.formatted_deletion_date;

                apply_tag_class(label, file_item.is_tagged);
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(label, file_item.is_tagged);
                });
                list_item.set_data<ulong>("trash_date_tag_id", tag_handler_id);
            });

            trash_date_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                ulong tag_handler_id = list_item.get_data<ulong>("trash_date_tag_id");
                if (tag_handler_id != 0 && file_item != null) {
                    file_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("trash_date_tag_id", 0);
                }
            });

            trash_date_col = new Gtk.ColumnViewColumn("Date Deleted", trash_date_factory);
            trash_date_col.id = "trash_date";
            trash_date_col.fixed_width = 160;
            trash_date_col.resizable = true;
            trash_date_col.sorter = new Gtk.CustomSorter((a, b) => {
                var item_a = (FileItem) a;
                var item_b = (FileItem) b;
                if (item_a.is_parent_dir) return -1;
                if (item_b.is_parent_dir) return 1;
                return (item_a.trash_deletion_date ?? "").collate(item_b.trash_deletion_date ?? "");
            });

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

                attach_item_click_controllers(list_item, box);
            });

            super_name_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var box = (Gtk.Box) list_item.child;
                var image = (Gtk.Image) box.get_first_child();
                var label = (Gtk.Label) image.get_next_sibling();

                image.gicon = file_item.icon;
                if (file_item.is_symlink && file_item.symlink_target != null && file_item.symlink_target.length > 0) {
                    label.label = @"$(file_item.display_name) -> $(file_item.symlink_target)";
                    box.tooltip_text = @"$(file_item.display_name) -> $(file_item.symlink_target)";
                } else {
                    label.label = file_item.display_name;
                    box.tooltip_text = null;
                }

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
                var box = list_item.child as Gtk.Box;
                if (box != null) {
                    box.tooltip_text = null;
                }
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

                attach_item_click_controllers(list_item, label);
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

                attach_item_click_controllers(list_item, label);
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

                attach_item_click_controllers(list_item, label);
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

                attach_item_click_controllers(list_item, label);
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
                    // Hide ".." parent folder in thumbnail grid mode for a clean Nautilus-like appearance
                    if (view_mode == PanelViewMode.GRID) {
                        return false;
                    }
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
                    if (!is_shift_navigating) {
                        shift_anchor_pos = selection_model.selected;
                    }
                }
                update_trash_restore_button();
            });

            column_view.model = null;
            column_view.activate.connect(on_item_activated);
            attach_view_controllers(column_view);

            super_column_view.model = null;
            super_column_view.activate.connect(on_item_activated);
            attach_view_controllers(super_column_view);

            // 2. GridView (Brief View)
            grid_view = new Gtk.GridView(null, create_brief_factory());
            grid_view.orientation = Gtk.Orientation.HORIZONTAL;
            grid_view.max_columns = 40;
            grid_view.min_columns = 1;
            grid_view.add_css_class("file-list-view");
            grid_view.activate.connect(on_item_activated);
            attach_view_controllers(grid_view);

            // 3. GridView (Thumbnail / Grid View)
            thumbnail_grid_view = new Gtk.GridView(null, create_grid_factory());
            thumbnail_grid_view.orientation = Gtk.Orientation.VERTICAL;
            thumbnail_grid_view.max_columns = 15;
            thumbnail_grid_view.min_columns = 1;
            thumbnail_grid_view.add_css_class("file-list-view");
            thumbnail_grid_view.add_css_class("thumbnail-grid-view");
            thumbnail_grid_view.activate.connect(on_item_activated);
            attach_view_controllers(thumbnail_grid_view);

            update_active_view_model();

            var scroll_ctrl = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.VERTICAL);
            scroll_ctrl.scroll.connect((dx, dy) => {
                var state = scroll_ctrl.get_current_event_state();
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (dy < 0) {
                        zoom_in();
                    } else if (dy > 0) {
                        zoom_out();
                    }
                    return true;
                }
                return false;
            });
            thumbnail_grid_view.add_controller(scroll_ctrl);

            // 4. Quick Filter Bar (Ctrl+S)
            build_filter_bar();

            // 5. Stack to switch between Detailed, Brief, Super Detailed and Grid view
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

            var brief_scroll_ctrl = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.BOTH_AXES);
            brief_scroll_ctrl.scroll.connect((dx, dy) => {
                var state = brief_scroll_ctrl.get_current_event_state();
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (dy < 0) {
                        zoom_in();
                    } else if (dy > 0) {
                        zoom_out();
                    }
                    return true;
                }

                // Normal mouse wheel: scroll columns horizontally in brief view
                var hadj = brief_scrolled.get_hadjustment();
                if (hadj != null) {
                    double delta = (dy != 0.0) ? dy : dx;
                    double step = double.max(40.0, ConfigManager.get_instance().brief_column_width * 0.5);
                    double new_val = hadj.get_value() + (delta * step);
                    new_val = double.max(hadj.get_lower(), double.min(hadj.get_upper() - hadj.get_page_size(), new_val));
                    hadj.set_value(new_val);
                    return true;
                }
                return false;
            });
            brief_scrolled.add_controller(brief_scroll_ctrl);

            view_stack.add_named(brief_scrolled, "brief");

            super_scrolled = new Gtk.ScrolledWindow();
            super_scrolled.hexpand = true;
            super_scrolled.vexpand = true;
            super_scrolled.child = super_column_view;
            view_stack.add_named(super_scrolled, "super");

            thumbnail_scrolled = new Gtk.ScrolledWindow();
            thumbnail_scrolled.hexpand = true;
            thumbnail_scrolled.vexpand = true;
            thumbnail_scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
            thumbnail_scrolled.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            thumbnail_scrolled.child = thumbnail_grid_view;
            view_stack.add_named(thumbnail_scrolled, "grid");

            view_stack.visible_child_name = (view_mode == PanelViewMode.DETAILED) ? "full" : view_mode.to_string_id();
            append(view_stack);
        }

        private void build_trash_banner() {
            trash_banner_revealer = new Gtk.Revealer();
            trash_banner_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            trash_banner_revealer.transition_duration = 200;
            trash_banner_revealer.reveal_child = false;

            trash_banner_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            trash_banner_box.add_css_class("trash-banner");

            var trash_icon = new Gtk.Image.from_icon_name("user-trash-symbolic");
            trash_icon.pixel_size = 18;
            trash_banner_box.append(trash_icon);

            trash_banner_label = new Gtk.Label("Trash");
            trash_banner_label.add_css_class("trash-banner-title");
            trash_banner_label.xalign = 0.0f;
            trash_banner_label.hexpand = true;
            trash_banner_box.append(trash_banner_label);

            var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            trash_restore_btn = new Gtk.Button.with_label("Restore Selected");
            trash_restore_btn.icon_name = "edit-undo-symbolic";
            trash_restore_btn.add_css_class("suggested-action");
            trash_restore_btn.tooltip_text = "Restore selected or tagged items to their original locations";
            trash_restore_btn.sensitive = false;
            trash_restore_btn.clicked.connect(() => {
                restore_requested();
            });
            btn_box.append(trash_restore_btn);

            trash_empty_btn = new Gtk.Button.with_label("Empty Trash");
            trash_empty_btn.icon_name = "user-trash-symbolic";
            trash_empty_btn.add_css_class("destructive-action");
            trash_empty_btn.tooltip_text = "Permanently delete all items from Trash";
            trash_empty_btn.sensitive = false;
            trash_empty_btn.clicked.connect(() => {
                empty_trash_requested();
            });
            btn_box.append(trash_empty_btn);

            trash_banner_box.append(btn_box);
            trash_banner_revealer.child = trash_banner_box;

            prepend(trash_banner_revealer);
        }

        public void update_trash_banner_state() {
            if (trash_banner_revealer == null) return;
            if (!is_trash_location()) {
                trash_banner_revealer.reveal_child = false;
                return;
            }

            trash_banner_revealer.reveal_child = true;

            uint count = 0;
            int64 bytes = 0;
            uint n = store.get_n_items();
            for (uint i = 0; i < n; i++) {
                var it = (FileItem) store.get_item(i);
                if (it != null && !it.is_parent_dir) {
                    count++;
                    bytes += it.size;
                }
            }

            if (count == 0) {
                trash_banner_label.label = "Trash is empty";
                trash_empty_btn.sensitive = false;
            } else {
                trash_banner_label.label = @"Trash contains $count items ($(format_size(bytes)))";
                trash_empty_btn.sensitive = true;
            }

            update_trash_restore_button();
        }

        public void update_trash_restore_button() {
            if (!is_trash_location() || trash_restore_btn == null) return;

            var tagged = get_tagged_items();
            if (tagged.length > 0) {
                trash_restore_btn.sensitive = true;
                trash_restore_btn.label = @"Restore Selected ($(tagged.length))";
            } else {
                var sel = get_selected_item();
                if (sel != null && !sel.is_parent_dir) {
                    trash_restore_btn.sensitive = true;
                    trash_restore_btn.label = "Restore Selected";
                } else {
                    trash_restore_btn.sensitive = false;
                    trash_restore_btn.label = "Restore Selected";
                }
            }
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
                bool is_shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                if (keyval == Gdk.Key.Down) {
                    if (is_shift) {
                        handle_shift_arrow_navigation(Gdk.Key.Down);
                        return Gdk.EVENT_STOP;
                    }
                    uint cur = selection_model.selected;
                    uint total = sort_model.get_n_items();
                    if (total > 0 && cur + 1 < total) {
                        selection_model.selected = cur + 1;
                        scroll_to_selected();
                    }
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Up) {
                    if (is_shift) {
                        handle_shift_arrow_navigation(Gdk.Key.Up);
                        return Gdk.EVENT_STOP;
                    }
                    uint cur = selection_model.selected;
                    if (cur > 0) {
                        selection_model.selected = cur - 1;
                        scroll_to_selected();
                    }
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Page_Down) {
                    if (is_shift) {
                        handle_shift_arrow_navigation(Gdk.Key.Page_Down);
                        return Gdk.EVENT_STOP;
                    }
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
                    if (is_shift) {
                        handle_shift_arrow_navigation(Gdk.Key.Page_Up);
                        return Gdk.EVENT_STOP;
                    }
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
            key_ctrl.key_released.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R) {
                    is_shift_navigating = false;
                    if (selection_model.selected != Gtk.INVALID_LIST_POSITION) {
                        shift_anchor_pos = selection_model.selected;
                    }
                }
            });
            filter_entry.add_controller(key_ctrl);

            filter_box.append(filter_entry);
            append(filter_box);
        }

        private void attach_view_controllers(Gtk.Widget target_view) {
            var key_controller = new Gtk.EventControllerKey();
            key_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key_controller.key_pressed.connect((keyval, keycode, state) => {
                uint latin_key = KeyUtils.to_latin(keyval, keycode);
                bool is_shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                bool is_ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
                bool is_alt = (state & Gdk.ModifierType.ALT_MASK) != 0;

                if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R) {
                    if (!is_shift_navigating && selection_model.selected != Gtk.INVALID_LIST_POSITION) {
                        shift_anchor_pos = selection_model.selected;
                    }
                }

                if (keyval == Gdk.Key.Escape && is_filter_active) {
                    hide_filter();
                    return Gdk.EVENT_STOP;
                }

                // Insert / KP_Insert: Toggle tag on current item and advance cursor down
                if (keyval == Gdk.Key.Insert || keyval == Gdk.Key.KP_Insert) {
                    toggle_tag_current_item();
                    return Gdk.EVENT_STOP;
                }

                // Shift + navigation keys (arrows, PgUp/PgDn, Home/End)
                if (is_shift && !is_ctrl && !is_alt) {
                    if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down ||
                        keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up ||
                        keyval == Gdk.Key.Left || keyval == Gdk.Key.KP_Left ||
                        keyval == Gdk.Key.Right || keyval == Gdk.Key.KP_Right ||
                        keyval == Gdk.Key.Page_Down || keyval == Gdk.Key.KP_Page_Down ||
                        keyval == Gdk.Key.Page_Up || keyval == Gdk.Key.KP_Page_Up ||
                        keyval == Gdk.Key.Home || keyval == Gdk.Key.KP_Home ||
                        keyval == Gdk.Key.End || keyval == Gdk.Key.KP_End) {
                        handle_shift_arrow_navigation(keyval);
                        return Gdk.EVENT_STOP;
                    }
                }

                if (keyval == Gdk.Key.BackSpace) {
                    go_up();
                    return Gdk.EVENT_STOP;
                }
                if (latin_key == Gdk.Key.h && is_ctrl) {
                    toggle_hidden_requested();
                    return Gdk.EVENT_STOP;
                }
                if ((latin_key == Gdk.Key.r || keyval == Gdk.Key.r || keyval == Gdk.Key.R) &&
                    is_ctrl && !is_alt && !is_shift) {
                    refresh();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl+Space: calculate folder or file size
                if (keyval == Gdk.Key.space && is_ctrl) {
                    calculate_selected_size();
                    return Gdk.EVENT_STOP;
                }

                // Ctrl++ or Ctrl+= : zoom in grid
                if ((keyval == Gdk.Key.plus || keyval == Gdk.Key.equal || keyval == Gdk.Key.KP_Add) && is_ctrl) {
                    if (view_mode == PanelViewMode.GRID) {
                        zoom_in();
                        return Gdk.EVENT_STOP;
                    }
                }

                // Ctrl+- : zoom out grid
                if ((keyval == Gdk.Key.minus || keyval == Gdk.Key.KP_Subtract) && is_ctrl) {
                    if (view_mode == PanelViewMode.GRID) {
                        zoom_out();
                        return Gdk.EVENT_STOP;
                    }
                }

                // Ctrl+0 : reset grid zoom
                if ((keyval == Gdk.Key.@0 || keyval == Gdk.Key.KP_0) && is_ctrl) {
                    if (view_mode == PanelViewMode.GRID) {
                        zoom_reset();
                        return Gdk.EVENT_STOP;
                    }
                }

                // Alt+T: toggle Brief / Full view mode
                if (latin_key == Gdk.Key.t && is_alt) {
                    toggle_view_mode();
                    return Gdk.EVENT_STOP;
                }

                // Alt+Up: Go to parent directory
                if (keyval == Gdk.Key.Up && is_alt) {
                    go_up();
                    return Gdk.EVENT_STOP;
                }

                // Left Arrow: Jump to top/first item (Full view or leftmost column in Brief view)
                if (keyval == Gdk.Key.Left && !is_ctrl && !is_alt && !is_shift) {
                    if (handle_left_arrow()) {
                        return Gdk.EVENT_STOP;
                    }
                    return Gdk.EVENT_PROPAGATE;
                }

                // Right Arrow: Jump to end/last item (Full view or rightmost column in Brief view)
                if (keyval == Gdk.Key.Right && !is_ctrl && !is_alt && !is_shift) {
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

            key_controller.key_released.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R) {
                    is_shift_navigating = false;
                    if (selection_model.selected != Gtk.INVALID_LIST_POSITION) {
                        shift_anchor_pos = selection_model.selected;
                    }
                }
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
                if (!is_active) {
                    page_activated();
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
            } else if (view_mode == PanelViewMode.SUPER) {
                switch_view_mode(PanelViewMode.GRID);
            } else {
                switch_view_mode(PanelViewMode.BRIEF);
            }
        }

        public void switch_view_mode(PanelViewMode mode) {
            view_mode = mode;
            update_active_view_model();
            view_stack.visible_child_name = (view_mode == PanelViewMode.DETAILED) ? "full" : view_mode.to_string_id();
            if (custom_filter != null) {
                custom_filter.changed(Gtk.FilterChange.DIFFERENT);
            }
            if (custom_master_sorter != null) {
                custom_master_sorter.changed(Gtk.SorterChange.DIFFERENT);
            }
            if (mode == PanelViewMode.GRID && thumbnail_grid_view != null) {
                thumbnail_grid_view.factory = create_grid_factory();
            }
            grab_focus_to_list();
            scroll_to_selected();
            view_mode_changed();
        }

        public void apply_sort(string sort_col, string sort_order) {
            this.sort_column_id = (sort_col == "size" || sort_col == "mtime" || sort_col == "owner" || sort_col == "group" || sort_col == "perm") ? sort_col : "name";
            this.sort_order_str = (sort_order == "desc") ? "desc" : "asc";

            Gtk.ColumnViewColumn target_col = name_col;
            if (sort_column_id == "size") {
                target_col = size_col;
            } else if (sort_column_id == "mtime") {
                target_col = time_col;
            }
            Gtk.SortType target_dir = (sort_order_str == "desc") ? Gtk.SortType.DESCENDING : Gtk.SortType.ASCENDING;
            if (column_view != null) {
                column_view.sort_by_column(target_col, target_dir);
            }

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
            if (super_column_view != null) {
                super_column_view.sort_by_column(super_target_col, target_dir);
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

                attach_item_click_controllers(list_item, box);
            });

            brief_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var box = (Gtk.Box) list_item.child;
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

        private Gtk.SignalListItemFactory create_grid_factory() {
            var grid_factory = new Gtk.SignalListItemFactory();
            var config = ConfigManager.get_instance();
            int tile_size = config.grid_tile_size;
            if (tile_size < 30) tile_size = 30;
            if (tile_size > 390) tile_size = 390;
            int icon_size = int.max(16, (int)(tile_size * 0.7));

            grid_factory.setup.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
                box.halign = Gtk.Align.CENTER;
                box.valign = Gtk.Align.START;
                box.margin_start = 6;
                box.margin_end = 6;
                box.margin_top = 6;
                box.margin_bottom = 6;

                var img_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                img_box.add_css_class("thumbnail-img-box");
                img_box.halign = Gtk.Align.CENTER;
                img_box.valign = Gtk.Align.CENTER;

                var picture = new Gtk.Picture();
                picture.can_shrink = true;
                picture.content_fit = Gtk.ContentFit.COVER;
                picture.hexpand = true;
                picture.vexpand = true;

                var icon = new Gtk.Image();
                icon.hexpand = true;
                icon.vexpand = true;

                img_box.append(picture);
                img_box.append(icon);

                var label = new Gtk.Label("");
                label.xalign = 0.5f;
                label.justify = Gtk.Justification.CENTER;
                label.wrap = true;
                label.wrap_mode = Pango.WrapMode.WORD_CHAR;
                label.lines = 2;
                label.ellipsize = Pango.EllipsizeMode.END;

                box.append(img_box);
                box.append(label);
                list_item.child = box;

                attach_item_click_controllers(list_item, box);
            });

            grid_factory.bind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                var file_item = (FileItem) list_item.item;
                var box = (Gtk.Box) list_item.child;
                var img_box = (Gtk.Box) box.get_first_child();
                var picture = (Gtk.Picture) img_box.get_first_child();
                var icon = (Gtk.Image) picture.get_next_sibling();
                var label = (Gtk.Label) img_box.get_next_sibling();

                img_box.width_request = tile_size;
                img_box.height_request = tile_size;
                box.width_request = tile_size + 16;
                label.max_width_chars = int.max(8, tile_size / 9);

                label.label = file_item.display_name;
                box.tooltip_text = file_item.display_name;

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
                apply_tag_class(img_box, file_item.is_tagged);

                // Clean up any previous binding on this recycled list_item
                cleanup_grid_item_binding(list_item);
                list_item.set_data<FileItem?>("grid_bound_item", file_item);

                // Connect thumbnail and tag notification handlers BEFORE requesting thumbnail
                // so that synchronous cache resolutions or immediate updates are never missed
                unowned FileItem target_item = file_item;
                unowned Gtk.Picture target_pic = picture;
                unowned Gtk.Image target_icon = icon;
                ulong thumb_handler_id = file_item.notify["thumbnail-paintable"].connect(() => {
                    if (target_item.thumbnail_paintable != null) {
                        target_pic.paintable = target_item.thumbnail_paintable;
                        target_pic.visible = true;
                        target_icon.visible = false;
                    }
                });
                list_item.set_data<ulong>("grid_thumb_id", thumb_handler_id);

                unowned Gtk.Label target_label = label;
                unowned Gtk.Box target_img_box = img_box;
                ulong tag_handler_id = file_item.notify["is-tagged"].connect(() => {
                    apply_tag_class(target_label, target_item.is_tagged);
                    apply_tag_class(target_img_box, target_item.is_tagged);
                });
                list_item.set_data<ulong>("grid_tag_id", tag_handler_id);

                if (file_item.thumbnail_paintable != null) {
                    picture.paintable = file_item.thumbnail_paintable;
                    picture.visible = true;
                    icon.visible = false;
                } else {
                    picture.visible = false;
                    picture.paintable = null;
                    icon.gicon = file_item.icon;
                    icon.pixel_size = icon_size;
                    icon.visible = true;

                    ThumbnailService.request_thumbnail(file_item);

                    // Re-check in case request_thumbnail resolved synchronously from cache
                    if (file_item.thumbnail_paintable != null) {
                        picture.paintable = file_item.thumbnail_paintable;
                        picture.visible = true;
                        icon.visible = false;
                    }
                }
            });

            grid_factory.unbind.connect((item) => {
                var list_item = (Gtk.ListItem) item;
                cleanup_grid_item_binding(list_item);
                var box = list_item.child as Gtk.Box;
                if (box != null) {
                    box.tooltip_text = null;
                    var img_box = box.get_first_child() as Gtk.Box;
                    if (img_box != null) {
                        var picture = img_box.get_first_child() as Gtk.Picture;
                        if (picture != null) {
                            picture.paintable = null;
                        }
                    }
                }
            });

            return grid_factory;
        }

        private void cleanup_grid_item_binding(Gtk.ListItem list_item) {
            var bound_item = list_item.get_data<FileItem?>("grid_bound_item");
            if (bound_item != null) {
                if (bound_item.thumbnail_paintable == null) {
                    ThumbnailService.cancel_request(bound_item);
                }

                ulong thumb_handler_id = list_item.get_data<ulong>("grid_thumb_id");
                if (thumb_handler_id != 0) {
                    bound_item.disconnect(thumb_handler_id);
                    list_item.set_data<ulong>("grid_thumb_id", 0);
                }

                ulong tag_handler_id = list_item.get_data<ulong>("grid_tag_id");
                if (tag_handler_id != 0) {
                    bound_item.disconnect(tag_handler_id);
                    list_item.set_data<ulong>("grid_tag_id", 0);
                }
                list_item.set_data<FileItem?>("grid_bound_item", null);
            }
        }

        private uint save_config_timeout_id = 0;
        private void debounce_save_config() {
            if (save_config_timeout_id != 0) {
                GLib.Source.remove(save_config_timeout_id);
                save_config_timeout_id = 0;
            }
            save_config_timeout_id = GLib.Timeout.add(500, () => {
                ConfigManager.get_instance().save();
                save_config_timeout_id = 0;
                return GLib.Source.REMOVE;
            });
        }

        public void set_grid_zoom(int size) {
            int clamped = int.max(30, int.min(390, (size / 30) * 30));
            if (clamped < 30) clamped = 30;
            var config = ConfigManager.get_instance();
            if (config.grid_tile_size == clamped) return;
            config.grid_tile_size = clamped;
            debounce_save_config();
            update_grid_tile_size();
        }

        public void zoom_in() {
            var config = ConfigManager.get_instance();
            set_grid_zoom(config.grid_tile_size + 30);
        }

        public void zoom_out() {
            var config = ConfigManager.get_instance();
            set_grid_zoom(config.grid_tile_size - 30);
        }

        public void zoom_reset() {
            set_grid_zoom(120);
        }

        public void update_grid_tile_size() {
            if (thumbnail_grid_view != null) {
                thumbnail_grid_view.factory = create_grid_factory();
            }
        }

        public void set_active(bool active) {
            if (is_active == active) return;
            is_active = active;
            if (active) {
                add_css_class("active-page");
                remove_css_class("inactive-page");
                if (selection_model.selected == Gtk.INVALID_LIST_POSITION) {
                    if (saved_selected_pos != Gtk.INVALID_LIST_POSITION && saved_selected_pos < sort_model.get_n_items()) {
                        selection_model.selected = saved_selected_pos;
                    } else if (sort_model.get_n_items() > 0) {
                        selection_model.selected = (sort_model.get_n_items() > 1 && ((FileItem) sort_model.get_item(0)).is_parent_dir) ? 1 : 0;
                    }
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
                if (grid_view != null && !grid_view.has_focus) grid_view.grab_focus();
            } else if (view_mode == PanelViewMode.GRID) {
                if (thumbnail_grid_view != null && !thumbnail_grid_view.has_focus) thumbnail_grid_view.grab_focus();
            } else if (view_mode == PanelViewMode.SUPER) {
                if (super_column_view != null && !super_column_view.has_focus) super_column_view.grab_focus();
            } else {
                if (column_view != null && !column_view.has_focus) column_view.grab_focus();
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
                } else if (view_mode == PanelViewMode.GRID && thumbnail_scrolled != null) {
                    var vadj = thumbnail_scrolled.get_vadjustment();
                    if (vadj != null) vadj.set_value(vadj.get_lower());
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
                } else if (view_mode == PanelViewMode.GRID && thumbnail_scrolled != null) {
                    var vadj = thumbnail_scrolled.get_vadjustment();
                    if (vadj != null) vadj.set_value(vadj.get_upper() - vadj.get_page_size());
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
            } else if (view_mode == PanelViewMode.GRID) {
                thumbnail_grid_view.scroll_to(pos, Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT, null);
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
            if (rows > 0) return rows;
            int height = grid_view.get_height();
            if (height > 0) {
                rows = (uint)(height / 28);
            }
            return rows > 0 ? rows : 1;
        }

        public bool handle_left_arrow() {
            if (view_mode == PanelViewMode.GRID) {
                return false;
            }
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
            if (view_mode == PanelViewMode.GRID) {
                return false;
            }
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
        public void update_columns_for_current_location() {
            bool in_trash = is_trash_location();
            if (in_trash == currently_in_trash_columns) {
                return;
            }
            currently_in_trash_columns = in_trash;

            var config = ConfigManager.get_instance();
            bool prev_updating = updating_columns;
            updating_columns = true;

            var cols_model = column_view.get_columns();
            while (cols_model.get_n_items() > 0) {
                column_view.remove_column((Gtk.ColumnViewColumn) cols_model.get_item(0));
            }

            if (in_trash) {
                if (name_col != null) column_view.append_column(name_col);
                if (trash_orig_col != null) column_view.append_column(trash_orig_col);
                if (size_col != null) column_view.append_column(size_col);
                if (trash_date_col != null) column_view.append_column(trash_date_col);
                if (dummy_col != null) column_view.append_column(dummy_col);
            } else {
                updating_columns = false;
                apply_columns_order(config.col_order);
                updating_columns = true;
            }

            updating_columns = prev_updating;
        }

        public void apply_columns_order(string[] order) {
            if (currently_in_trash_columns) return;
            var cols_model = column_view.get_columns();
            uint n = cols_model.get_n_items();

            // Check if current order already matches the requested order
            bool matches = true;
            uint real_cols = 0;
            for (uint i = 0; i < n; i++) {
                var c = (Gtk.ColumnViewColumn) cols_model.get_item(i);
                if (c.id == "dummy") continue;
                if (real_cols >= order.length || c.id != order[real_cols]) {
                    matches = false;
                    break;
                }
                real_cols++;
            }
            if (matches && real_cols == order.length) {
                return;
            }

            bool prev_updating = updating_columns;
            updating_columns = true;
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
            updating_columns = prev_updating;
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
            if (updating_columns || currently_in_trash_columns) return;
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
            if (updating_columns || currently_in_trash_columns) return;
            save_columns_to_config();
            columns_layout_changed();
        }

        public void save_columns_to_config() {
            if (currently_in_trash_columns) return;
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
            if (updating_columns) return;
            var config = ConfigManager.get_instance();
            updating_columns = true;

            apply_columns_order(config.col_order);

            // Detailed view
            if (config.col_width_name > 30 && name_col.fixed_width != config.col_width_name) name_col.fixed_width = config.col_width_name;
            if (config.col_width_size > 30 && size_col.fixed_width != config.col_width_size) size_col.fixed_width = config.col_width_size;
            if (config.col_width_mtime > 30 && time_col.fixed_width != config.col_width_mtime) time_col.fixed_width = config.col_width_mtime;

            // Super Detailed view
            if (config.super_col_width_name > 30 && super_name_col.fixed_width != config.super_col_width_name) super_name_col.fixed_width = config.super_col_width_name;
            if (config.super_col_width_owner > 20 && super_owner_col.fixed_width != config.super_col_width_owner) super_owner_col.fixed_width = config.super_col_width_owner;
            if (config.super_col_width_group > 20 && super_group_col.fixed_width != config.super_col_width_group) super_group_col.fixed_width = config.super_col_width_group;
            if (config.super_col_width_perm > 20 && super_perm_col.fixed_width != config.super_col_width_perm) super_perm_col.fixed_width = config.super_col_width_perm;
            if (config.super_col_width_size > 20 && super_size_col.fixed_width != config.super_col_width_size) super_size_col.fixed_width = config.super_col_width_size;

            updating_columns = false;
        }

        private void apply_tag_class(Gtk.Widget widget, bool is_tagged) {
            if (is_tagged) {
                widget.add_css_class("file-item-tagged");
            } else {
                widget.remove_css_class("file-item-tagged");
            }
        }

        private void attach_item_click_controllers(Gtk.ListItem list_item, Gtk.Widget widget) {
            var left_click = new Gtk.GestureClick();
            left_click.button = 1;
            left_click.pressed.connect((n_press, x, y) => {
                on_item_left_clicked(list_item, left_click, n_press);
            });
            widget.add_controller(left_click);

            var right_click = new Gtk.GestureClick();
            right_click.button = 3;
            right_click.pressed.connect(() => {
                on_item_right_clicked(list_item);
            });
            widget.add_controller(right_click);
        }

        private void on_item_left_clicked(Gtk.ListItem list_item, Gtk.GestureClick gesture, int n_press) {
            page_activated();
            grab_focus_to_list();

            uint pos = list_item.position;
            if (pos == Gtk.INVALID_LIST_POSITION || pos >= sort_model.get_n_items()) return;

            var state = gesture.get_current_event_state();
            bool is_shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool is_ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;

            if (is_shift) {
                gesture.set_state(Gtk.EventSequenceState.CLAIMED);
                handle_shift_click(pos);
            } else if (is_ctrl) {
                gesture.set_state(Gtk.EventSequenceState.CLAIMED);
                handle_ctrl_click(pos);
            } else {
                handle_normal_click(pos);
            }
        }

        private void handle_shift_click(uint pos) {
            uint total = sort_model.get_n_items();
            if (total == 0 || pos >= total) return;

            uint anchor = shift_anchor_pos;
            if (anchor == Gtk.INVALID_LIST_POSITION || anchor >= total) {
                anchor = (selection_model.selected != Gtk.INVALID_LIST_POSITION && selection_model.selected < total)
                    ? selection_model.selected
                    : pos;
            }

            uint start = uint.min(anchor, pos);
            uint end = uint.max(anchor, pos);
            for (uint i = start; i <= end; i++) {
                var it = (FileItem) sort_model.get_item(i);
                if (it != null && !it.is_parent_dir) {
                    it.is_tagged = true;
                }
            }

            selection_model.selected = pos;
            saved_selected_pos = pos;
            shift_anchor_pos = anchor;
            scroll_to_selected();
            update_status_bar();
        }

        private void handle_ctrl_click(uint pos) {
            uint total = sort_model.get_n_items();
            if (total == 0 || pos >= total) return;

            var it = (FileItem) sort_model.get_item(pos);
            if (it != null && !it.is_parent_dir) {
                it.is_tagged = !it.is_tagged;
            }

            selection_model.selected = pos;
            saved_selected_pos = pos;
            shift_anchor_pos = pos;
            scroll_to_selected();
            update_status_bar();
        }

        private void handle_normal_click(uint pos) {
            selection_model.selected = pos;
            saved_selected_pos = pos;
            shift_anchor_pos = pos;
        }

        private void on_item_right_clicked(Gtk.ListItem list_item) {
            page_activated();
            grab_focus_to_list();

            var file_item = (FileItem) list_item.item;
            if (file_item == null || file_item.is_parent_dir) {
                return;
            }

            file_item.is_tagged = !file_item.is_tagged;
            uint pos = list_item.position;
            if (pos != Gtk.INVALID_LIST_POSITION && pos < sort_model.get_n_items()) {
                selection_model.selected = pos;
                saved_selected_pos = pos;
                shift_anchor_pos = pos;
            }
            update_status_bar();
        }

        private uint get_grid_columns() {
            uint cols = 0;
            var child = thumbnail_grid_view.get_first_child();
            while (child != null) {
                Graphene.Rect bounds;
                if (child.compute_bounds(thumbnail_grid_view, out bounds)) {
                    if (bounds.get_y() > 1.0f) {
                        break;
                    }
                }
                cols++;
                child = child.get_next_sibling();
            }
            if (cols > 0) return cols;

            int width = thumbnail_grid_view.get_width();
            var config = ConfigManager.get_instance();
            int tile_size = config.grid_tile_size;
            if (tile_size < 30) tile_size = 30;
            int col_width = tile_size + 16;
            if (width > 0 && col_width > 0) {
                cols = (uint)(width / col_width);
            }
            return cols > 0 ? cols : 1;
        }

        private void handle_shift_arrow_navigation(uint keyval) {
            uint total = sort_model.get_n_items();
            if (total == 0) return;

            uint cur_pos = selection_model.selected;
            if (cur_pos == Gtk.INVALID_LIST_POSITION || cur_pos >= total) {
                cur_pos = (saved_selected_pos < total) ? saved_selected_pos : 0;
            }

            if (shift_anchor_pos == Gtk.INVALID_LIST_POSITION || shift_anchor_pos >= total) {
                shift_anchor_pos = cur_pos;
            }
            is_shift_navigating = true;

            uint target_pos = cur_pos;

            if (view_mode == PanelViewMode.BRIEF) {
                uint rows = get_brief_rows_per_col();
                if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
                    target_pos = uint.min(cur_pos + 1, total - 1);
                } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
                    target_pos = (cur_pos > 0) ? cur_pos - 1 : 0;
                } else if (keyval == Gdk.Key.Right || keyval == Gdk.Key.KP_Right || keyval == Gdk.Key.Page_Down || keyval == Gdk.Key.KP_Page_Down) {
                    target_pos = uint.min(cur_pos + rows, total - 1);
                } else if (keyval == Gdk.Key.Left || keyval == Gdk.Key.KP_Left || keyval == Gdk.Key.Page_Up || keyval == Gdk.Key.KP_Page_Up) {
                    target_pos = (cur_pos >= rows) ? cur_pos - rows : 0;
                } else if (keyval == Gdk.Key.Home || keyval == Gdk.Key.KP_Home) {
                    target_pos = 0;
                } else if (keyval == Gdk.Key.End || keyval == Gdk.Key.KP_End) {
                    target_pos = total - 1;
                }
            } else if (view_mode == PanelViewMode.GRID) {
                uint cols = get_grid_columns();
                if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
                    target_pos = uint.min(cur_pos + cols, total - 1);
                } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
                    target_pos = (cur_pos >= cols) ? cur_pos - cols : 0;
                } else if (keyval == Gdk.Key.Right || keyval == Gdk.Key.KP_Right) {
                    target_pos = uint.min(cur_pos + 1, total - 1);
                } else if (keyval == Gdk.Key.Left || keyval == Gdk.Key.KP_Left) {
                    target_pos = (cur_pos > 0) ? cur_pos - 1 : 0;
                } else if (keyval == Gdk.Key.Page_Down || keyval == Gdk.Key.KP_Page_Down) {
                    target_pos = uint.min(cur_pos + cols * 4, total - 1);
                } else if (keyval == Gdk.Key.Page_Up || keyval == Gdk.Key.KP_Page_Up) {
                    target_pos = (cur_pos >= cols * 4) ? cur_pos - cols * 4 : 0;
                } else if (keyval == Gdk.Key.Home || keyval == Gdk.Key.KP_Home) {
                    target_pos = 0;
                } else if (keyval == Gdk.Key.End || keyval == Gdk.Key.KP_End) {
                    target_pos = total - 1;
                }
            } else {
                // Detailed or Super Detailed
                if (keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down) {
                    target_pos = uint.min(cur_pos + 1, total - 1);
                } else if (keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up) {
                    target_pos = (cur_pos > 0) ? cur_pos - 1 : 0;
                } else if (keyval == Gdk.Key.Page_Down || keyval == Gdk.Key.KP_Page_Down) {
                    target_pos = uint.min(cur_pos + 20, total - 1);
                } else if (keyval == Gdk.Key.Page_Up || keyval == Gdk.Key.KP_Page_Up) {
                    target_pos = (cur_pos >= 20) ? cur_pos - 20 : 0;
                } else if (keyval == Gdk.Key.Home || keyval == Gdk.Key.KP_Home || keyval == Gdk.Key.Left || keyval == Gdk.Key.KP_Left) {
                    target_pos = 0;
                } else if (keyval == Gdk.Key.End || keyval == Gdk.Key.KP_End || keyval == Gdk.Key.Right || keyval == Gdk.Key.KP_Right) {
                    target_pos = total - 1;
                }
            }

            uint start = uint.min(uint.min(shift_anchor_pos, cur_pos), target_pos);
            uint end = uint.max(uint.max(shift_anchor_pos, cur_pos), target_pos);
            for (uint i = start; i <= end; i++) {
                var it = (FileItem) sort_model.get_item(i);
                if (it != null && !it.is_parent_dir) {
                    it.is_tagged = true;
                }
            }

            selection_model.selected = target_pos;
            saved_selected_pos = target_pos;
            scroll_to_selected();
            update_status_bar();
        }

        private void update_active_view_model() {
            column_view.model = (view_mode == PanelViewMode.DETAILED) ? selection_model : null;
            super_column_view.model = (view_mode == PanelViewMode.SUPER) ? selection_model : null;
            grid_view.model = (view_mode == PanelViewMode.BRIEF) ? selection_model : null;
            thumbnail_grid_view.model = (view_mode == PanelViewMode.GRID) ? selection_model : null;
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
                grab_focus_to_list();
                scroll_to_selected();
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
            update_trash_restore_button();
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
            } else if (is_trash_location()) {
                restore_item_requested(item);
            } else if (item.is_dir) {
                load_directory(item.file);
            } else if (is_archive_location()) {
                open_archive_file(item);
            } else if (ArchiverRegistry.get_instance().is_archive_filename(item.name)) {
                string? p = item.file.get_path();
                if (p != null) {
                    load_directory(File.new_for_uri(@"archive://$p"));
                } else {
                    open_file_with_default_app(item);
                }
            } else {
                open_file_with_default_app(item);
            }
        }

        private bool is_opening_archive_file = false;

        private void open_archive_file(FileItem item) {
            if (is_opening_archive_file) return;
            is_opening_archive_file = true;

            string? archive_path;
            string? inner_path;
            if (!ArchiveTreeService.split_archive_uri(item.file.get_uri(), out archive_path, out inner_path)) {
                is_opening_archive_file = false;
                return;
            }
            if (archive_path == null || inner_path == null) {
                is_opening_archive_file = false;
                return;
            }

            status_label.label = @"Extracting $(item.name) for preview...";
            var temp_file = ArchiveTreeService.get_temp_extracted_file(archive_path, inner_path);

            extract_and_launch_file.begin(archive_path, inner_path, temp_file, (obj, res) => {
                is_opening_archive_file = false;
                update_status_bar();
            });
        }

        private async void extract_and_launch_file(string archive_path, string inner_path, File temp_file) {
            bool is_retry = false;
            while (true) {
                try {
                    yield ArchiveTreeService.extract_single_file_to(archive_path, inner_path, temp_file, null);
                    var launcher = new Gtk.FileLauncher(temp_file);
                    yield launcher.launch(get_root() as Gtk.Window, null);
                    break;
                } catch (ArchivePasswordError e) {
                    is_retry = (e is ArchivePasswordError.INVALID);
                    string? pwd = yield ArchivePasswordDialog.prompt_async(get_root() as Gtk.Window, Path.get_basename(archive_path), is_retry);
                    if (pwd == null) {
                        status_label.label = "Extraction cancelled";
                        break;
                    }
                    ArchiveTreeService.set_cached_password(archive_path, pwd);
                } catch (Error e) {
                    error_occurred("Preview Error", @"Cannot extract $(Path.get_basename(inner_path)): $(e.message)");
                    break;
                }
            }
        }

        public void go_up() {
            if (showing_search_results && current_directory != null) {
                load_directory(current_directory);
                return;
            }
            if (is_archive_location()) {
                string? archive_path;
                string? inner_path;
                if (ArchiveTreeService.split_archive_uri(current_directory.get_uri(), out archive_path, out inner_path)) {
                    if (inner_path == null || inner_path.length == 0) {
                        // At root of archive, go up to host directory on disk and select the archive file
                        var parent_dir = File.new_for_path(Path.get_dirname(archive_path));
                        string archive_name = Path.get_basename(archive_path);
                        load_directory(parent_dir, archive_name);
                        return;
                    } else {
                        // Inside archive subfolder, go up to parent inner folder
                        int last_slash = inner_path.last_index_of_char('/');
                        string prev_folder = (last_slash >= 0) ? inner_path.substring(last_slash + 1) : inner_path;
                        string parent_inner = (last_slash >= 0) ? inner_path.substring(0, last_slash) : "";
                        string parent_uri = (parent_inner.length > 0)
                            ? @"archive://$(archive_path)/$(parent_inner)"
                            : @"archive://$(archive_path)";
                        load_directory(File.new_for_uri(parent_uri), prev_folder);
                        return;
                    }
                }
            }
            var parent = current_directory.get_parent();
            if (parent != null) {
                string prev_folder_name = current_directory.get_basename();
                load_directory(parent, prev_folder_name);
            }
        }

        public void apply_show_hidden(bool hidden) {
            if (this.show_hidden != hidden) {
                this.show_hidden = hidden;
                refresh();
            }
        }

        public void refresh() {
            if (showing_search_results) {
                update_status_bar();
                return;
            }
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
            if (showing_search_results) {
                showing_search_results = false;
                if (custom_title == "Search") {
                    custom_title = null;
                }
            }
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
            directory_changed(dir);
            update_columns_for_current_location();
            update_trash_banner_state();

            load_directory_async.begin(dir, cursor_select_name, preserved_tags, load_cancellable);
        }

        private async void load_archive_directory_async(File dir, string? target_select_name, GenericSet<string>? preserved_tags, Cancellable cancellable) {
            string? archive_path;
            string? inner_path;
            if (!ArchiveTreeService.split_archive_uri(dir.get_uri(), out archive_path, out inner_path)) {
                error_occurred("Archive Error", @"Invalid archive path: $(dir.get_uri())");
                status_label.label = "Error opening archive";
                return;
            }

            status_label.label = @"Reading archive $(Path.get_basename(archive_path))...";

            ArchiveTree tree;
            while (true) {
                try {
                    tree = yield ArchiveTreeService.get_tree(archive_path, cancellable);
                    break;
                } catch (ArchivePasswordError e) {
                    bool is_retry = (e is ArchivePasswordError.INVALID);
                    string? pwd = yield ArchivePasswordDialog.prompt_async(get_root() as Gtk.Window, Path.get_basename(archive_path), is_retry);
                    if (pwd == null) {
                        status_label.label = "Archive access cancelled";
                        return;
                    }
                    ArchiveTreeService.set_cached_password(archive_path, pwd);
                } catch (IOError.CANCELLED e) {
                    return;
                } catch (Error e) {
                    error_occurred("Archive Error", @"Cannot read archive $(Path.get_basename(archive_path)): $(e.message)");
                    status_label.label = @"Error: $(e.message)";
                    return;
                }
            }

            if (cancellable.is_cancelled()) {
                return;
            }

            var items = new GenericArray<FileItem>();

            // Add parent ".." entry
            if (inner_path == null || inner_path.length == 0) {
                var parent_disk = File.new_for_path(Path.get_dirname(archive_path));
                items.add(new FileItem.for_parent(parent_disk));
            } else {
                int last_slash = inner_path.last_index_of_char('/');
                string parent_inner = (last_slash >= 0) ? inner_path.substring(0, last_slash) : "";
                string parent_uri = (parent_inner.length > 0)
                    ? @"archive://$(archive_path)/$(parent_inner)"
                    : @"archive://$(archive_path)";
                var parent_arc = File.new_for_uri(parent_uri);
                items.add(new FileItem.for_parent(parent_arc));
            }

            var children = ArchiveTreeService.list_directory(tree, inner_path != null ? inner_path : "", dir);
            uint count_files = 0;
            uint count_dirs = 0;
            int64 total_bytes = 0;

            for (uint i = 0; i < children.length; i++) {
                var item = children.get(i);
                bool is_hidden = item.is_hidden || item.name.has_prefix(".");
                if (is_hidden && !show_hidden) {
                    continue;
                }
                if (preserved_tags != null && preserved_tags.contains(item.name)) {
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

            var array = new Object[items.length];
            for (int i = 0; i < items.length; i++) {
                array[i] = items[i];
            }
            uint old_count = store.get_n_items();
            for (uint i = 0; i < old_count; i++) {
                var old_item = (FileItem) store.get_item(i);
                if (old_item != null) {
                    old_item.thumbnail_paintable = null;
                }
            }
            store.splice(0, old_count, array);
            ThumbnailService.malloc_trim(0);

            update_columns_for_current_location();
            update_trash_banner_state();
            current_dir_stats = @"$(count_dirs) folders, $(count_files) files ($(format_size(total_bytes))) [Archive]";
            update_status_bar();

            uint total_items = sort_model.get_n_items();
            if (total_items > 0) {
                uint target_index = 0;
                bool found_target = false;

                if (target_select_name != null && target_select_name.length > 0) {
                    for (uint i = 0; i < total_items; i++) {
                        var it = (FileItem) sort_model.get_item(i);
                        if (it != null && it.name == target_select_name) {
                            target_index = i;
                            found_target = true;
                            break;
                        }
                    }
                }

                if (!found_target && total_items > 1) {
                    var first_it = (FileItem) sort_model.get_item(0);
                    if (first_it != null && first_it.is_parent_dir) {
                        target_index = 1;
                    }
                }

                if (is_active) {
                    selection_model.selected = target_index;
                    saved_selected_pos = target_index;
                    shift_anchor_pos = target_index;
                    scroll_to_selected();
                    grab_focus_to_list();
                } else {
                    saved_selected_pos = target_index;
                    shift_anchor_pos = target_index;
                    selection_model.selected = Gtk.INVALID_LIST_POSITION;
                }
            }
        }

        private async void load_directory_async(File dir, string? target_select_name, GenericSet<string>? preserved_tags, Cancellable cancellable) {
            string? scheme = dir.get_uri_scheme();
            if (scheme == "archive") {
                yield load_archive_directory_async(dir, target_select_name, preserved_tags, cancellable);
                return;
            }

            status_label.label = "Scanning directory...";

            if (scheme != null && scheme != "file") {
                status_label.label = "Connecting…";
                try {
                    var root = get_root() as Gtk.Window;
                    string? agent = null;
                    var main = root as MainWindow;
                    if (main != null) {
                        agent = main.terminal_ssh_agent();
                    }
                    File opened = yield RemoteMount.prepare(dir, agent, root, cancellable);
                    if (!opened.equal(dir)) {
                        dir = opened;
                        current_directory = opened;
                        directory_changed(opened);
                    }
                } catch (IOError.CANCELLED e) {
                    return;
                } catch (Error e) {
                    error_occurred("Connection Error", e.message);
                    status_label.label = @"Error: $(e.message)";
                    return;
                }
                if (cancellable.is_cancelled()) {
                    return;
                }
                status_label.label = "Scanning directory...";
            }

            var items = new GenericArray<FileItem>();

            var parent = dir.get_parent();
            if (parent != null) {
                items.add(new FileItem.for_parent(parent));
            }

            uint count_files = 0;
            uint count_dirs = 0;
            int64 total_bytes = 0;

            try {
                string attributes = "standard::name,standard::display-name,standard::type,standard::size,standard::is-hidden,standard::is-symlink,standard::symlink-target,standard::icon,time::modified,owner::user,owner::group,unix::uid,unix::user-name,unix::gid,unix::group-name,unix::mode";
                if (dir.get_uri_scheme() == "trash") {
                    attributes += ",trash::orig-path,trash::deletion-date";
                }

                var enumerator = yield dir.enumerate_children_async(
                    attributes,
                    FileQueryInfoFlags.NONE,
                    Priority.DEFAULT,
                    cancellable
                );

                while (true) {
                    var files = yield enumerator.next_files_async(500, Priority.DEFAULT, cancellable);
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
            uint old_count = store.get_n_items();
            for (uint i = 0; i < old_count; i++) {
                var old_item = (FileItem) store.get_item(i);
                if (old_item != null) {
                    old_item.thumbnail_paintable = null;
                    if (old_item.is_thumbnail_requested) {
                        ThumbnailService.cancel_request(old_item);
                    }
                }
            }
            store.splice(0, old_count, array);
            ThumbnailService.malloc_trim(0);

            string free_space_str = "";
            try {
                var fs_info = yield dir.query_filesystem_info_async("filesystem::free", Priority.DEFAULT, cancellable);
                uint64 free_space = fs_info.get_attribute_uint64("filesystem::free");
                free_space_str = @" | Free: $(format_size((int64)free_space))";
            } catch (Error e) {
            }

            update_columns_for_current_location();
            update_trash_banner_state();
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
                    saved_selected_pos = target_index;
                    shift_anchor_pos = target_index;
                    scroll_to_selected();
                    grab_focus_to_list();
                } else {
                    saved_selected_pos = target_index;
                    shift_anchor_pos = target_index;
                    selection_model.selected = Gtk.INVALID_LIST_POSITION;
                }
            } else {
                selection_model.selected = Gtk.INVALID_LIST_POSITION;
                shift_anchor_pos = Gtk.INVALID_LIST_POSITION;
            }
        }

        public void cleanup() {
            shift_anchor_pos = Gtk.INVALID_LIST_POSITION;
            is_shift_navigating = false;
            if (load_cancellable != null) {
                load_cancellable.cancel();
                load_cancellable = null;
            }
            if (dir_calc_cancellable != null) {
                dir_calc_cancellable.cancel();
                dir_calc_cancellable = null;
            }
            if (save_config_timeout_id != 0) {
                GLib.Source.remove(save_config_timeout_id);
                save_config_timeout_id = 0;
                ConfigManager.get_instance().save();
            }
            uint count = store.get_n_items();
            for (uint i = 0; i < count; i++) {
                var it = (FileItem) store.get_item(i);
                if (it != null) {
                    it.thumbnail_paintable = null;
                    if (it.is_thumbnail_requested) {
                        ThumbnailService.cancel_request(it);
                    }
                }
            }
            store.remove_all();
            ThumbnailService.malloc_trim(0);
        }

        ~FilePanelPage() {
            cleanup();
        }
    }
}
