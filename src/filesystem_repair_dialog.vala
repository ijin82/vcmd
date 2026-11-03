namespace VCommander {

    public class FilesystemRepairDialog : Object {
        private static FilesystemRepairDialog? active = null;

        private unowned MainWindow window;
        private LocationItem item;
        private string? device_node = null;
        private string? fs_type = null;
        private uint64 device_size = 0;
        private string? udisks_block_path = null;
        private string? initial_error = null;
        private string? repaired_mount_path = null;
        private bool is_running = false;

        private Adw.Dialog dialog;
        private Adw.ActionRow dev_row;
        private Adw.ActionRow fs_row;
        private Adw.ActionRow size_row;
        private Adw.ActionRow mount_row;
        private Gtk.TextView log_view;
        private Gtk.TextBuffer log_buffer;
        private Gtk.ScrolledWindow log_scroll;
        private Gtk.Spinner spinner;
        private Gtk.Label status_label;
        private Gtk.Button cancel_button;
        private Gtk.Button check_button;
        private Gtk.Button repair_button;
        private Gtk.Button terminal_button;
        private Gtk.Button open_button;
        private Adw.Banner error_banner;

        public static void show(MainWindow window, LocationItem item, string? initial_error = null) {
            if (active != null) {
                active.dialog.present(window);
                return;
            }
            var dlg = new FilesystemRepairDialog(window, item, initial_error);
            dlg.dialog.present(window);
        }

        private FilesystemRepairDialog(MainWindow window, LocationItem item, string? initial_error = null) {
            this.window = window;
            this.item = item;
            this.initial_error = initial_error;
            active = this;

            device_node = VolumeService.resolve_device_node(item);
            if (device_node != null) {
                udisks_block_path = VolumeService.get_udisks_block_path(device_node);
            }

            dialog = new Adw.Dialog();
            dialog.title = @"Check & Repair: $(item.name)";
            dialog.content_width = 580;
            dialog.content_height = 560;

            dialog.closed.connect(() => {
                active = null;
            });

            var toolbar_view = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.show_title = true;
            toolbar_view.add_top_bar(header);

            var main_scroll = new Gtk.ScrolledWindow();
            main_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            main_scroll.hexpand = true;
            main_scroll.vexpand = true;

            var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 14);
            content_box.margin_start = 20;
            content_box.margin_end = 20;
            content_box.margin_top = 16;
            content_box.margin_bottom = 16;

            error_banner = new Adw.Banner("");
            if (initial_error != null && initial_error.length > 0) {
                error_banner.title = "Mount Error: " + initial_error;
                error_banner.revealed = true;
            } else {
                error_banner.revealed = false;
            }
            content_box.append(error_banner);

            var info_group = new Adw.PreferencesGroup();
            info_group.title = "Storage Device Information";

            dev_row = new Adw.ActionRow();
            dev_row.title = "Device Node";
            dev_row.subtitle = device_node ?? "Unknown";
            info_group.add(dev_row);

            fs_row = new Adw.ActionRow();
            fs_row.title = "Filesystem";
            fs_row.subtitle = "Detecting...";
            info_group.add(fs_row);

            size_row = new Adw.ActionRow();
            size_row.title = "Partition Size";
            size_row.subtitle = "Detecting...";
            info_group.add(size_row);

            mount_row = new Adw.ActionRow();
            mount_row.title = "Current Status";
            mount_row.subtitle = item.is_mounted ? (item.subtitle ?? "Mounted") : "Unmounted";
            info_group.add(mount_row);

            content_box.append(info_group);

            var explanation = new Gtk.Label("Running fsck inspects filesystem consistency and repairs damaged clusters, superblocks, and metadata. The device will be unmounted during this operation.");
            explanation.xalign = 0;
            explanation.wrap = true;
            explanation.add_css_class("dim-label");
            content_box.append(explanation);

            // Log View
            var log_heading = new Gtk.Label("Diagnostic Output");
            log_heading.xalign = 0;
            log_heading.add_css_class("heading");
            content_box.append(log_heading);

            log_buffer = new Gtk.TextBuffer(null);
            log_view = new Gtk.TextView.with_buffer(log_buffer);
            log_view.monospace = true;
            log_view.editable = false;
            log_view.cursor_visible = false;
            log_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            log_view.margin_start = 10;
            log_view.margin_end = 10;
            log_view.margin_top = 8;
            log_view.margin_bottom = 8;

            log_scroll = new Gtk.ScrolledWindow();
            log_scroll.set_child(log_view);
            log_scroll.min_content_height = 150;
            log_scroll.max_content_height = 200;
            log_scroll.add_css_class("card");
            content_box.append(log_scroll);

            // Status Indicator Box
            var status_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
            status_box.valign = Gtk.Align.CENTER;

            spinner = new Gtk.Spinner();
            spinner.visible = false;
            status_box.append(spinner);

            status_label = new Gtk.Label("Ready to check filesystem.");
            status_label.xalign = 0;
            status_label.hexpand = true;
            status_box.append(status_label);

            content_box.append(status_box);

            main_scroll.set_child(content_box);
            toolbar_view.set_content(main_scroll);

            // Action Bar (Bottom)
            var action_bar = new Gtk.ActionBar();

            cancel_button = new Gtk.Button.with_label("Close");
            cancel_button.clicked.connect(() => {
                dialog.close();
            });
            action_bar.pack_start(cancel_button);

            terminal_button = new Gtk.Button.with_label("Terminal fsck...");
            terminal_button.icon_name = "utilities-terminal-symbolic";
            terminal_button.tooltip_text = "Run fsck interactively in the built-in terminal";
            terminal_button.clicked.connect(() => {
                if (device_node != null) {
                    dialog.close();
                    window.open_terminal_with_command(@"pkexec fsck -y '$device_node'");
                }
            });
            action_bar.pack_start(terminal_button);

            check_button = new Gtk.Button.with_label("Check Only");
            check_button.icon_name = "system-search-symbolic";
            check_button.tooltip_text = "Verify filesystem consistency without making modifications";
            check_button.clicked.connect(() => {
                run_operation.begin(false);
            });
            action_bar.pack_end(check_button);

            repair_button = new Gtk.Button.with_label("Repair Filesystem");
            repair_button.icon_name = "system-run-symbolic";
            repair_button.add_css_class("suggested-action");
            repair_button.tooltip_text = "Automatically repair damaged clusters and file system structures";
            repair_button.clicked.connect(() => {
                run_operation.begin(true);
            });
            action_bar.pack_end(repair_button);

            open_button = new Gtk.Button.with_label("Open in Files");
            open_button.icon_name = "folder-symbolic";
            open_button.add_css_class("suggested-action");
            open_button.visible = false;
            open_button.clicked.connect(() => {
                if (repaired_mount_path != null && window.active_panel != null) {
                    window.active_panel.load_directory(File.new_for_path(repaired_mount_path));
                    window.active_panel.grab_focus_to_list();
                }
                dialog.close();
            });
            action_bar.pack_end(open_button);

            toolbar_view.add_bottom_bar(action_bar);
            dialog.set_child(toolbar_view);

            query_device_info.begin();
        }

        private async void query_device_info() {
            if (device_node == null || udisks_block_path == null) {
                status_label.label = "Could not identify underlying block device node.";
                check_button.sensitive = false;
                repair_button.sensitive = false;
                terminal_button.sensitive = false;
                return;
            }

            try {
                var bus = yield Bus.get(BusType.SYSTEM, null);

                // Query IdType
                try {
                    var type_res = yield bus.call(
                        "org.freedesktop.UDisks2",
                        udisks_block_path,
                        "org.freedesktop.DBus.Properties",
                        "Get",
                        new Variant("(ss)", "org.freedesktop.UDisks2.Block", "IdType"),
                        new VariantType("(v)"),
                        DBusCallFlags.NONE,
                        4000,
                        null
                    );
                    Variant inner_type;
                    type_res.get("(v)", out inner_type);
                    fs_type = inner_type.get_string();
                } catch (Error err) {
                    // ignore
                }

                // If not found in UDisks, check proc mounts
                if (fs_type == null && item.file != null && item.file.get_path() != null) {
                    fs_type = VolumeService.get_fs_type_for_mount_path(item.file.get_path());
                }

                // Query Size
                try {
                    var size_res = yield bus.call(
                        "org.freedesktop.UDisks2",
                        udisks_block_path,
                        "org.freedesktop.DBus.Properties",
                        "Get",
                        new Variant("(ss)", "org.freedesktop.UDisks2.Block", "Size"),
                        new VariantType("(v)"),
                        DBusCallFlags.NONE,
                        4000,
                        null
                    );
                    Variant inner_size;
                    size_res.get("(v)", out inner_size);
                    device_size = inner_size.get_uint64();
                } catch (Error err) {
                    // ignore
                }

            } catch (Error e) {
                // Ignore DBus connection errors
            }

            fs_row.subtitle = (fs_type != null && fs_type.length > 0) ? fs_type.up() : "Unknown";
            size_row.subtitle = (device_size > 0) ? format_size(device_size) : "Unknown";

            string? cur_mp = VolumeService.get_mount_path_for_device(device_node);
            if (cur_mp != null) {
                mount_row.subtitle = @"Mounted at $cur_mp";
            } else {
                mount_row.subtitle = "Unmounted";
            }
        }

        private void append_log(string text) {
            Gtk.TextIter end_iter;
            log_buffer.get_end_iter(out end_iter);
            log_buffer.insert(ref end_iter, text, -1);

            // Auto-scroll to end
            Idle.add(() => {
                var mark = log_buffer.get_insert();
                log_view.scroll_to_mark(mark, 0.0, false, 0.0, 0.0);
                return Source.REMOVE;
            });
        }

        private void clear_log() {
            log_buffer.set_text("", -1);
        }

        private void set_busy(bool busy, string status_msg = "") {
            is_running = busy;
            spinner.visible = busy;
            if (busy) {
                spinner.start();
            } else {
                spinner.stop();
            }

            status_label.label = status_msg;
            check_button.sensitive = !busy;
            repair_button.sensitive = !busy;
            terminal_button.sensitive = !busy;
            cancel_button.sensitive = !busy;
        }

        private async void run_operation(bool do_repair) {
            if (device_node == null || udisks_block_path == null) {
                status_label.label = "Invalid block device.";
                return;
            }

            set_busy(true, do_repair ? "Repairing filesystem..." : "Checking filesystem...");
            clear_log();
            open_button.visible = false;

            append_log(@"=== Starting Filesystem $(do_repair ? "Repair" : "Check") ===\n");
            append_log(@"Target device: $device_node\n");
            if (fs_type != null) {
                append_log(@"Filesystem type: $(fs_type.up())\n");
            }

            try {
                var bus = yield Bus.get(BusType.SYSTEM, null);

                // 1. Unmount if currently mounted
                string? cur_mount = VolumeService.get_mount_path_for_device(device_node);
                if (cur_mount != null) {
                    append_log(@"\nUnmounting $device_node from $cur_mount...\n");
                    try {
                        yield bus.call(
                            "org.freedesktop.UDisks2",
                            udisks_block_path,
                            "org.freedesktop.UDisks2.Filesystem",
                            "Unmount",
                            new Variant.tuple(new Variant[] {
                                new Variant.array(new VariantType("{sv}"), new Variant[] {})
                            }),
                            null,
                            DBusCallFlags.NONE,
                            30000,
                            null
                        );
                        append_log("Device unmounted successfully.\n");
                        mount_row.subtitle = "Unmounted";
                    } catch (Error unmount_err) {
                        append_log(@"Warning while unmounting: $(unmount_err.message)\n");
                    }
                }

                // 2. Call Check or Repair
                string method_name = do_repair ? "Repair" : "Check";
                append_log(@"\nInvoking UDisks2 $method_name for $device_node...\n");

                var call_res = yield bus.call(
                    "org.freedesktop.UDisks2",
                    udisks_block_path,
                    "org.freedesktop.UDisks2.Filesystem",
                    method_name,
                    new Variant.tuple(new Variant[] {
                        new Variant.array(new VariantType("{sv}"), new Variant[] {})
                    }),
                    new VariantType("(b)"),
                    DBusCallFlags.NONE,
                    300000, // 5 minutes max
                    null
                );

                bool result_flag = false;
                call_res.get("(b)", out result_flag);

                if (do_repair) {
                    if (result_flag) {
                        append_log("\n✓ Repair completed successfully!\n");
                        status_label.label = "Filesystem repaired successfully.";
                        error_banner.revealed = false;
                    } else {
                        append_log("\n⚠ Repair tool completed, but reported device could not be fully fixed.\n");
                        status_label.label = "Filesystem could not be fully repaired.";
                    }
                } else {
                    if (result_flag) {
                        append_log("\n✓ Filesystem is consistent and clean. No errors found.\n");
                        status_label.label = "Filesystem is clean. No errors found.";
                        error_banner.revealed = false;
                    } else {
                        append_log("\n⚠ Filesystem contains inconsistencies or corrupted structures.\n");
                        status_label.label = "Errors detected. Click 'Repair Filesystem' to fix them.";
                    }
                }

                // 3. Remount if clean or successfully repaired
                if (result_flag) {
                    append_log(@"\nRemounting $device_node...\n");
                    try {
                        var mount_res = yield bus.call(
                            "org.freedesktop.UDisks2",
                            udisks_block_path,
                            "org.freedesktop.UDisks2.Filesystem",
                            "Mount",
                            new Variant.tuple(new Variant[] {
                                new Variant.array(new VariantType("{sv}"), new Variant[] {})
                            }),
                            new VariantType("(s)"),
                            DBusCallFlags.NONE,
                            30000,
                            null
                        );
                        string new_mount_path = "";
                        mount_res.get("(s)", out new_mount_path);
                        repaired_mount_path = new_mount_path;
                        mount_row.subtitle = @"Mounted at $new_mount_path";
                        append_log(@"Mounted at $new_mount_path\n");
                        open_button.visible = true;
                    } catch (Error mount_err) {
                        append_log(@"Note: Device was not automatically remounted: $(mount_err.message)\n");
                    }
                }

            } catch (Error e) {
                append_log(@"\n❌ Diagnostic Output:\n$(e.message)\n");
                if (!do_repair) {
                    status_label.label = "Errors detected. Click 'Repair Filesystem' to fix.";
                    append_log("\n⚠ Inconsistencies detected. You can repair them by clicking 'Repair Filesystem'.\n");
                } else {
                    status_label.label = "Repair failed or requires manual intervention.";
                    append_log("\n⚠ If automatic repair fails, try clicking 'Terminal fsck...' for interactive repair.\n");
                }
            } finally {
                set_busy(false);
            }
        }
    }
}
