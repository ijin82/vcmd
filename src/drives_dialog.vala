namespace VCommander {

    public class LocationRow : Adw.ActionRow {
        public LocationItem item { get; private set; }

        public signal void eject_clicked(LocationItem item);
        public signal void repair_clicked(LocationItem item);

        public LocationRow(LocationItem item) {
            Object();
            this.item = item;
            this.title = Markup.escape_text(item.name);
            if (item.subtitle != null && item.subtitle.length > 0) {
                this.subtitle = Markup.escape_text(item.subtitle);
            }
            this.activatable = true;
            this.focusable = true;

            if (item.icon != null) {
                var img = new Gtk.Image.from_gicon(item.icon);
                img.pixel_size = 20;
                this.add_prefix(img);
            }

            if (item.is_encrypted) {
                var lock_icon = new Gtk.Image.from_icon_name("channel-secure-symbolic");
                lock_icon.pixel_size = 16;
                lock_icon.valign = Gtk.Align.CENTER;
                lock_icon.add_css_class("dim-label");
                lock_icon.tooltip_text = item.is_mounted ? "Encrypted Volume (LUKS) — Unlocked" : "Encrypted Volume (LUKS) — Locked";
                this.add_suffix(lock_icon);
            }

            if (item.category == LocationCategory.DEVICE && item.id != "root" && (!item.is_encrypted || item.is_mounted)) {
                var repair_btn = new Gtk.Button.from_icon_name("system-run-symbolic");
                repair_btn.valign = Gtk.Align.CENTER;
                repair_btn.add_css_class("flat");
                repair_btn.add_css_class("circular");
                repair_btn.focusable = false;
                repair_btn.tooltip_text = "Check & Repair Filesystem (fsck) [r]";
                repair_btn.clicked.connect(() => {
                    repair_clicked(item);
                });
                this.add_suffix(repair_btn);
            }

            if (item.can_eject || item.can_unmount || (item.is_encrypted && item.is_mounted)) {
                var eject_btn = new Gtk.Button.from_icon_name("media-eject-symbolic");
                eject_btn.valign = Gtk.Align.CENTER;
                eject_btn.add_css_class("flat");
                eject_btn.add_css_class("circular");
                eject_btn.focusable = false;
                if (item.is_encrypted) {
                    eject_btn.tooltip_text = "Unmount & Lock Encrypted Volume [e]";
                } else if (item.category == LocationCategory.NETWORK) {
                    eject_btn.tooltip_text = "Disconnect";
                } else {
                    eject_btn.tooltip_text = "Eject / Unmount [e]";
                }
                eject_btn.clicked.connect(() => {
                    eject_clicked(item);
                });
                this.add_suffix(eject_btn);
            }
        }
    }

    public class DrivesDialog : Adw.Dialog {
        private static DrivesDialog? active_dialog = null;

        private unowned MainWindow window;
        private Gtk.ListBox list_box;
        private ulong changed_handler_id = 0;

        public static void show(MainWindow window) {
            if (active_dialog != null) {
                active_dialog.present(window);
                return;
            }
            var dlg = new DrivesDialog(window);
            dlg.present(window);
        }

        public static void toggle(MainWindow window) {
            if (active_dialog != null) {
                active_dialog.close();
            } else {
                show(window);
            }
        }

        public static bool is_open() {
            return active_dialog != null;
        }

        private DrivesDialog(MainWindow window) {
            Object();
            this.window = window;
            active_dialog = this;

            this.title = "Drives & Locations";
            this.content_width = 480;

            this.closed.connect(() => {
                if (changed_handler_id != 0) {
                    VolumeService.get_instance().disconnect(changed_handler_id);
                    changed_handler_id = 0;
                }
                active_dialog = null;
                if (window.active_panel != null) {
                    window.active_panel.grab_focus_to_list();
                }
            });

            var toolbar_view = new Adw.ToolbarView();

            var header_bar = new Adw.HeaderBar();
            header_bar.show_title = true;
            toolbar_view.add_top_bar(header_bar);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.propagate_natural_height = true;
            scrolled.max_content_height = 480;
            scrolled.min_content_height = 140;
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;

            list_box = new Gtk.ListBox();
            list_box.selection_mode = Gtk.SelectionMode.SINGLE;
            list_box.add_css_class("boxed-list");
            list_box.margin_start = 12;
            list_box.margin_end = 12;
            list_box.margin_top = 8;
            list_box.margin_bottom = 8;

            list_box.set_header_func((row, before) => {
                var cur_row = row as LocationRow;
                if (cur_row == null) return;

                if (before == null) {
                    row.set_header(create_section_header(category_title(cur_row.item.category)));
                    return;
                }

                var prev_row = before as LocationRow;
                if (prev_row != null && prev_row.item.category != cur_row.item.category) {
                    row.set_header(create_section_header(category_title(cur_row.item.category)));
                } else {
                    row.set_header(null);
                }
            });

            list_box.row_activated.connect((row) => {
                var loc_row = row as LocationRow;
                if (loc_row != null) {
                    on_item_activated(loc_row.item);
                }
            });

            var key_ctrl = new Gtk.EventControllerKey();
            key_ctrl.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            key_ctrl.key_pressed.connect((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    close();
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.F1 && (state & Gdk.ModifierType.CONTROL_MASK) != 0 && (state & (Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                    close();
                    return Gdk.EVENT_STOP;
                }
                if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.e || keyval == Gdk.Key.E) {
                    var sel = list_box.get_selected_row() as LocationRow;
                    if (sel != null && (sel.item.can_eject || sel.item.can_unmount || (sel.item.is_encrypted && sel.item.is_mounted))) {
                        handle_eject(sel.item);
                        return Gdk.EVENT_STOP;
                    }
                }
                if (keyval == Gdk.Key.r || keyval == Gdk.Key.R) {
                    var sel = list_box.get_selected_row() as LocationRow;
                    if (sel != null && sel.item.category == LocationCategory.DEVICE && sel.item.id != "root" && (!sel.item.is_encrypted || sel.item.is_mounted)) {
                        handle_repair(sel.item);
                        return Gdk.EVENT_STOP;
                    }
                }
                return Gdk.EVENT_PROPAGATE;
            });
            list_box.add_controller(key_ctrl);

            scrolled.set_child(list_box);
            toolbar_view.set_content(scrolled);

            // Bottom bar with action hints & close button
            var bottom_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            bottom_bar.margin_start = 14;
            bottom_bar.margin_end = 14;
            bottom_bar.margin_top = 6;
            bottom_bar.margin_bottom = 6;

            var hints_label = new Gtk.Label("↵ Open  •  e Eject  •  r Repair");
            hints_label.add_css_class("dim-label");
            hints_label.add_css_class("caption");
            bottom_bar.append(hints_label);

            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom_bar.append(spacer);

            var close_btn = new Gtk.Button.with_label("Close");
            close_btn.clicked.connect(() => {
                close();
            });
            bottom_bar.append(close_btn);

            toolbar_view.add_bottom_bar(bottom_bar);
            set_child(toolbar_view);

            populate_items(true);

            changed_handler_id = VolumeService.get_instance().changed.connect(() => {
                populate_items(false);
            });
        }

        private string category_title(LocationCategory cat) {
            switch (cat) {
                case LocationCategory.DEVICE:
                    return "Devices & Drives";
                case LocationCategory.NETWORK:
                    return "Network & Remote";
                case LocationCategory.PLACE:
                    return "Standard Places";
                case LocationCategory.ACTION:
                    return "Actions";
                default:
                    return "Locations";
            }
        }

        private Gtk.Widget create_section_header(string title) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            box.margin_top = 10;
            box.margin_bottom = 4;
            box.margin_start = 6;
            box.margin_end = 6;
            var label = new Gtk.Label(title);
            label.xalign = 0;
            label.add_css_class("heading");
            label.add_css_class("dim-label");
            box.append(label);
            return box;
        }

        public void populate_items(bool focus_first = false) {
            int prev_idx = -1;
            var cur_selected = list_box.get_selected_row();
            if (cur_selected != null) {
                prev_idx = cur_selected.get_index();
            }

            // Remove existing rows
            Gtk.Widget? child = list_box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                list_box.remove(child);
                child = next;
            }

            var locations = VolumeService.get_instance().get_locations();
            for (int i = 0; i < locations.length; i++) {
                var item = locations.get(i);
                var row = new LocationRow(item);
                row.eject_clicked.connect((it) => {
                    handle_eject(it);
                });
                row.repair_clicked.connect((it) => {
                    handle_repair(it);
                });
                list_box.append(row);
            }

            Idle.add(() => {
                int target_idx = focus_first ? 0 : (prev_idx >= 0 ? prev_idx : 0);
                var target_row = list_box.get_row_at_index(target_idx);
                if (target_row == null && target_idx > 0) {
                    target_row = list_box.get_row_at_index(0);
                }
                if (target_row != null) {
                    list_box.select_row(target_row);
                    target_row.grab_focus();
                }
                return Source.REMOVE;
            });
        }

        private void handle_eject(LocationItem item) {
            File? target_root = item.file;
            if (target_root == null && item.mount != null) {
                target_root = item.mount.get_root();
            }
            if (target_root != null) {
                window.handle_mount_removed(target_root);
            }

            // Evacuate any other mounts belonging to this same drive or volume as well
            var all_mounts = VolumeMonitor.get().get_mounts();
            foreach (var m in all_mounts) {
                if ((item.drive != null && m.get_drive() == item.drive) ||
                    (item.volume != null && m.get_volume() == item.volume) ||
                    (item.mount != null && m == item.mount)) {
                    var m_root = m.get_root();
                    if (m_root != null) {
                        window.handle_mount_removed(m_root);
                    }
                }
            }

            VolumeService.get_instance().unmount_or_eject.begin(item, window, (obj, res) => {
                bool ok = VolumeService.get_instance().unmount_or_eject.end(res);
                if (ok) {
                    string action_msg;
                    if (item.is_encrypted) {
                        action_msg = "Locked & Safely removed: ";
                    } else if (item.category == LocationCategory.NETWORK) {
                        action_msg = "Disconnected: ";
                    } else {
                        action_msg = "Safely removed: ";
                    }
                    window.show_command_toast(action_msg + item.name);
                    if (target_root != null) {
                        window.handle_mount_removed(target_root);
                    }
                } else {
                    window.show_command_toast("Could not eject: " + item.name);
                }
            });
        }

        private void handle_repair(LocationItem item) {
            close();
            window.prompt_filesystem_repair(item);
        }

        private void on_item_activated(LocationItem item) {
            close();

            if (item.category == LocationCategory.ACTION) {
                if (window.active_panel != null) {
                    ConnectDialog.show(window, window.active_panel);
                }
                return;
            }

            if (item.is_mounted && item.file != null) {
                if (window.active_panel != null) {
                    window.active_panel.load_directory(item.file);
                    window.active_panel.grab_focus_to_list();
                }
                return;
            }

            if (!item.is_mounted && item.volume != null) {
                VolumeService.get_instance().mount_volume.begin(item, window, (obj, res) => {
                    try {
                        var mounted_root = VolumeService.get_instance().mount_volume.end(res);
                        if (mounted_root != null && window.active_panel != null) {
                            window.active_panel.load_directory(mounted_root);
                            window.active_panel.grab_focus_to_list();
                        } else {
                            window.show_command_toast("Failed to mount: " + item.name);
                        }
                    } catch (Error e) {
                        if (e.code == IOError.FAILED_HANDLED || e.code == IOError.CANCELLED) {
                            return;
                        }
                        if (item.is_encrypted) {
                            window.show_command_toast("Failed to unlock: " + e.message);
                        } else {
                            window.prompt_filesystem_repair(item, e.message);
                        }
                    }
                });
            }
        }
    }
}
