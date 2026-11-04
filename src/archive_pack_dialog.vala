namespace VCommander {

    public class ArchivePackRequest : Object {
        public File destination_archive { get; construct set; }
        public ArchiveFormatInfo format { get; construct set; }
        public ArchiveCompressionLevel compression_level { get; construct set; }
        public string? password { get; construct set; default = null; }
        public bool delete_source_after_pack { get; construct set; default = false; }
        public GenericArray<FileItem> source_items { get; construct set; }

        public ArchivePackRequest(
            File destination_archive,
            ArchiveFormatInfo format,
            ArchiveCompressionLevel compression_level,
            string? password,
            bool delete_source_after_pack,
            GenericArray<FileItem> source_items
        ) {
            Object(
                destination_archive: destination_archive,
                format: format,
                compression_level: compression_level,
                password: password,
                delete_source_after_pack: delete_source_after_pack,
                source_items: source_items
            );
        }
    }

    public delegate void ArchivePackCallback(ArchivePackRequest request);

    public class ArchivePackDialog : Object {
        private static ArchivePackDialog? active = null;

        private unowned Gtk.Window parent_window;
        private unowned FilePanel active_panel;
        private unowned FilePanel opposite_panel;
        private GenericArray<FileItem> items;
        private ArchivePackCallback on_confirm;

        private Adw.Dialog dialog;
        private Adw.EntryRow dest_entry_row;
        private Adw.ComboRow format_combo_row;
        private Adw.ComboRow level_combo_row;
        private Adw.PasswordEntryRow password_row;
        private Adw.SwitchRow delete_switch_row;
        private Gtk.Button pack_button;

        private GenericArray<ArchiveFormatInfo> available_formats;
        private string current_base_dir = "";

        public static void show(
            Gtk.Window parent,
            FilePanel active_panel,
            FilePanel opposite_panel,
            GenericArray<FileItem> items,
            ArchivePackCallback callback
        ) {
            if (active != null) {
                active.dialog.present(parent);
                return;
            }

            var dlg = new ArchivePackDialog(parent, active_panel, opposite_panel, items, callback);
            dlg.dialog.present(parent);
        }

        private ArchivePackDialog(
            Gtk.Window parent,
            FilePanel active_panel,
            FilePanel opposite_panel,
            GenericArray<FileItem> items,
            ArchivePackCallback callback
        ) {
            this.parent_window = parent;
            this.active_panel = active_panel;
            this.opposite_panel = opposite_panel;
            this.items = items;
            this.on_confirm = callback;
            active = this;

            var registry = ArchiverRegistry.get_instance();
            available_formats = registry.get_available_pack_formats();

            build_ui();
        }

        private void build_ui() {
            dialog = new Adw.Dialog();
            dialog.title = "Pack to Archive";
            dialog.content_width = 540;
            dialog.content_height = 490;

            dialog.closed.connect(() => {
                active = null;
            });

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.show_title = true;

            var cancel_btn = new Gtk.Button.with_label("Cancel");
            cancel_btn.clicked.connect(() => {
                dialog.close();
            });
            header.pack_start(cancel_btn);

            pack_button = new Gtk.Button.with_label("Pack");
            pack_button.add_css_class("suggested-action");
            pack_button.clicked.connect(on_pack_clicked);
            header.pack_end(pack_button);

            toolbar.add_top_bar(header);

            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();

            // Destination archive path
            dest_entry_row = new Adw.EntryRow();
            dest_entry_row.title = "Archive Path and Name";
            dest_entry_row.text = calculate_default_destination();
            dest_entry_row.changed.connect(() => {
                validate_form();
            });
            group.add(dest_entry_row);

            // Format selector
            format_combo_row = new Adw.ComboRow();
            format_combo_row.title = "Archive Format";
            var format_names = new Gtk.StringList(null);
            for (uint i = 0; i < available_formats.length; i++) {
                var fmt = available_formats.get(i);
                format_names.append(fmt.name);
            }
            format_combo_row.model = format_names;
            format_combo_row.selected = 0; // Default to first available format (usually .zip or .tar.gz)
            format_combo_row.notify["selected"].connect(on_format_changed);
            group.add(format_combo_row);

            // Compression level
            level_combo_row = new Adw.ComboRow();
            level_combo_row.title = "Compression Level";
            var level_names = new Gtk.StringList(null);
            level_names.append(ArchiveCompressionLevel.NORMAL.to_display_string());
            level_names.append(ArchiveCompressionLevel.FAST.to_display_string());
            level_names.append(ArchiveCompressionLevel.STORE.to_display_string());
            level_names.append(ArchiveCompressionLevel.MAXIMUM.to_display_string());
            level_names.append(ArchiveCompressionLevel.ULTRA.to_display_string());
            level_combo_row.model = level_names;
            level_combo_row.selected = 0;
            group.add(level_combo_row);

            // Password field (for encrypted formats)
            password_row = new Adw.PasswordEntryRow();
            password_row.title = "Password (Optional)";
            group.add(password_row);

            // Delete after packing (move to archive)
            delete_switch_row = new Adw.SwitchRow();
            delete_switch_row.title = "Delete files after archiving";
            delete_switch_row.subtitle = "Move items into the archive";
            delete_switch_row.active = false;
            group.add(delete_switch_row);

            // Summary info row
            var info_row = new Adw.ActionRow();
            int64 total_bytes = 0;
            for (uint i = 0; i < items.length; i++) {
                total_bytes += items.get(i).size;
            }
            string formatted_size = format_size(total_bytes);
            if (items.length == 1) {
                info_row.title = @"Selected 1 item: '$(items.get(0).display_name)' ($formatted_size)";
            } else {
                info_row.title = @"Selected $(items.length) items ($formatted_size)";
            }
            info_row.subtitle = "Target engine: " + get_current_format_engine_label();
            group.add(info_row);

            page.add(group);
            toolbar.set_content(page);
            dialog.set_child(toolbar);

            // Initial format update
            update_format_capabilities();
            validate_form();
        }

        private string get_current_format_engine_label() {
            uint idx = format_combo_row.selected;
            if (idx < available_formats.length) {
                var fmt = available_formats.get(idx);
                return @"$(fmt.default_tool) ($(fmt.primary_extension))";
            }
            return "auto";
        }

        private void on_format_changed() {
            uint idx = format_combo_row.selected;
            if (idx >= available_formats.length) return;

            var fmt = available_formats.get(idx);
            update_format_capabilities();

            // Auto-update extension in destination path
            string cur_text = dest_entry_row.text.strip();
            if (cur_text.length > 0) {
                string dir_name = Path.get_dirname(cur_text);
                string base_name = Path.get_basename(cur_text);

                // Strip any existing archive extension
                string stripped_name = strip_known_archive_extension(base_name);
                string new_basename = stripped_name + fmt.primary_extension;
                dest_entry_row.text = Path.build_filename(dir_name, new_basename);
            }
        }

        private void update_format_capabilities() {
            uint idx = format_combo_row.selected;
            if (idx >= available_formats.length) return;

            var fmt = available_formats.get(idx);
            password_row.sensitive = fmt.supports_password;
            if (!fmt.supports_password) {
                password_row.text = "";
            }

            level_combo_row.sensitive = fmt.supports_compression_level;
        }

        private void validate_form() {
            string text = dest_entry_row.text.strip();
            pack_button.sensitive = (text.length > 0 && available_formats.length > 0);
        }

        private string calculate_default_destination() {
            // Prefer opposite panel's directory if valid, otherwise active panel's directory
            File? dest_dir = (opposite_panel != null) ? opposite_panel.current_directory : null;
            if (dest_dir == null || dest_dir.get_uri_scheme() == "trash") {
                dest_dir = active_panel.current_directory;
            }

            string base_dir = (dest_dir != null) ? (dest_dir.get_path() ?? dest_dir.get_parse_name()) : Environment.get_home_dir();
            current_base_dir = base_dir;

            string suggested_name = "archive";
            if (items.length == 1) {
                var item = items.get(0);
                suggested_name = strip_known_archive_extension(item.name);
                if (suggested_name.length == 0) suggested_name = item.name;
            } else if (items.length > 1 && active_panel.current_directory != null) {
                string? folder_name = active_panel.current_directory.get_basename();
                if (folder_name != null && folder_name.length > 0 && folder_name != "/") {
                    suggested_name = folder_name;
                }
            }

            string default_ext = (available_formats.length > 0) ? available_formats.get(0).primary_extension : ".zip";
            return Path.build_filename(base_dir, suggested_name + default_ext);
        }

        private string strip_known_archive_extension(string filename) {
            string lower = filename.down();
            string[] double_exts = { ".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tgz", ".tbz2", ".txz" };
            foreach (var ext in double_exts) {
                if (lower.has_suffix(ext)) {
                    return filename.substring(0, filename.length - ext.length);
                }
            }

            string[] single_exts = { ".zip", ".tar", ".7z", ".rar", ".iso", ".deb", ".rpm", ".cab", ".gz", ".xz", ".bz2", ".zst" };
            foreach (var ext in single_exts) {
                if (lower.has_suffix(ext)) {
                    return filename.substring(0, filename.length - ext.length);
                }
            }

            // Also strip ordinary single extension for single files (e.g. "document.pdf" -> "document")
            int last_dot = filename.last_index_of_char('.');
            if (last_dot > 0 && last_dot != filename.length - 1) {
                return filename.substring(0, last_dot);
            }

            return filename;
        }

        private ArchiveCompressionLevel get_selected_compression_level() {
            uint idx = level_combo_row.selected;
            switch (idx) {
                case 0: return ArchiveCompressionLevel.NORMAL;
                case 1: return ArchiveCompressionLevel.FAST;
                case 2: return ArchiveCompressionLevel.STORE;
                case 3: return ArchiveCompressionLevel.MAXIMUM;
                case 4: return ArchiveCompressionLevel.ULTRA;
                default: return ArchiveCompressionLevel.NORMAL;
            }
        }

        private void on_pack_clicked() {
            string dest_path = dest_entry_row.text.strip();
            if (dest_path.length == 0) return;

            uint format_idx = format_combo_row.selected;
            if (format_idx >= available_formats.length) return;
            var fmt = available_formats.get(format_idx);

            // Ensure destination has an extension
            if (!dest_path.down().has_suffix(fmt.primary_extension.down())) {
                dest_path += fmt.primary_extension;
            }

            var dest_file = File.new_for_path(dest_path);
            var parent_dir = dest_file.get_parent();

            if (parent_dir != null && !parent_dir.query_exists()) {
                var alert = new Adw.AlertDialog("Invalid Destination", @"Parent folder does not exist:\n$(parent_dir.get_parse_name())");
                alert.add_response("ok", "OK");
                alert.set_default_response("ok");
                alert.choose.begin(parent_window, null);
                return;
            }

            // Check if archive already exists
            if (dest_file.query_exists()) {
                var overwrite_alert = new Adw.AlertDialog(
                    "Archive Already Exists",
                    @"An archive named '$(dest_file.get_basename())' already exists at this location.\nDo you want to overwrite it?"
                );
                overwrite_alert.add_response("cancel", "Cancel");
                overwrite_alert.add_response("overwrite", "Overwrite");
                overwrite_alert.set_default_response("cancel");
                overwrite_alert.set_close_response("cancel");
                overwrite_alert.set_response_appearance("overwrite", Adw.ResponseAppearance.DESTRUCTIVE);

                overwrite_alert.choose.begin(parent_window, null, (obj, res) => {
                    string resp = overwrite_alert.choose.end(res);
                    if (resp == "overwrite") {
                        dispatch_pack_request(dest_file, fmt);
                    }
                });
                return;
            }

            dispatch_pack_request(dest_file, fmt);
        }

        private void dispatch_pack_request(File dest_file, ArchiveFormatInfo fmt) {
            string? pwd = password_row.text.strip();
            if (pwd != null && pwd.length == 0) pwd = null;

            var request = new ArchivePackRequest(
                dest_file,
                fmt,
                get_selected_compression_level(),
                pwd,
                delete_switch_row.active,
                items
            );

            dialog.close();
            on_confirm(request);
        }

        private string format_size(int64 bytes) {
            if (bytes < 1024) return @"$bytes B";
            double kb = (double)bytes / 1024.0;
            if (kb < 1024.0) return "%.1f KB".printf(kb);
            double mb = kb / 1024.0;
            if (mb < 1024.0) return "%.1f MB".printf(mb);
            double gb = mb / 1024.0;
            return "%.2f GB".printf(gb);
        }
    }
}
