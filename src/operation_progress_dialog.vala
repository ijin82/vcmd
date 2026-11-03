namespace VCommander {

    public class OperationProgressDialog : Adw.Dialog {
        private Gtk.Label item_label;
        private Gtk.Label details_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.Button cancel_button;
        private Cancellable cancellable;
        private bool is_finished = false;
        private bool is_synchronizing = false;

        private int64 last_update_time = 0;
        private uint pending_timeout_id = 0;
        private uint speed_timer_id = 0;
        private uint sync_pulse_timer_id = 0;

        private string pending_filename = "";
        private int64 pending_current_bytes = 0;
        private int64 pending_total_bytes = 0;

        private int64 last_speed_time = 0;
        private int64 last_speed_bytes = 0;
        private string current_speed_str = "";
        private string current_eta_str = "";

        public signal void cancelled();

        public OperationProgressDialog(string op_title, Cancellable cancellable) {
            this.cancellable = cancellable;

            set_title(op_title);
            set_content_width(480);
            set_content_height(190);

            var toolbar_view = new Adw.ToolbarView();

            var header_bar = new Adw.HeaderBar();
            header_bar.show_title = true;
            header_bar.show_start_title_buttons = false;
            header_bar.show_end_title_buttons = false;
            toolbar_view.add_top_bar(header_bar);

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            main_box.margin_start = 24;
            main_box.margin_end = 24;
            main_box.margin_top = 16;
            main_box.margin_bottom = 20;

            item_label = new Gtk.Label("Preparing operation...");
            item_label.xalign = 0.0f;
            item_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            item_label.add_css_class("dim-label");

            progress_bar = new Gtk.ProgressBar();
            progress_bar.fraction = 0.0;
            progress_bar.show_text = true;

            details_label = new Gtk.Label("");
            details_label.xalign = 0.0f;
            details_label.add_css_class("caption");

            var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            btn_box.halign = Gtk.Align.END;

            cancel_button = new Gtk.Button.with_label("Cancel");
            cancel_button.clicked.connect(() => {
                cancel_button.sensitive = false;
                item_label.label = "Cancelling...";
                if (!is_finished) {
                    cancellable.cancel();
                    cancelled();
                }
                force_close();
            });
            btn_box.append(cancel_button);

            main_box.append(item_label);
            main_box.append(progress_bar);
            main_box.append(details_label);
            main_box.append(btn_box);

            toolbar_view.set_content(main_box);
            set_child(toolbar_view);

            // Timer running once per second to compute transfer speed and ETA
            speed_timer_id = Timeout.add_seconds(1, on_speed_tick);

            closed.connect(() => {
                cleanup_timers();
                if (!is_finished) {
                    is_finished = true;
                    cancellable.cancel();
                    cancelled();
                }
            });
        }

        private void cleanup_timers() {
            if (pending_timeout_id != 0) {
                Source.remove(pending_timeout_id);
                pending_timeout_id = 0;
            }
            if (speed_timer_id != 0) {
                Source.remove(speed_timer_id);
                speed_timer_id = 0;
            }
            if (sync_pulse_timer_id != 0) {
                Source.remove(sync_pulse_timer_id);
                sync_pulse_timer_id = 0;
            }
        }

        private bool on_speed_tick() {
            if (is_finished) {
                speed_timer_id = 0;
                return Source.REMOVE;
            }
            if (is_synchronizing) return Source.CONTINUE;

            int64 now = GLib.get_monotonic_time();
            if (last_speed_time == 0) {
                last_speed_time = now;
                last_speed_bytes = pending_current_bytes;
                return Source.CONTINUE;
            }

            int64 elapsed_us = now - last_speed_time;
            if (elapsed_us < 500000) return Source.CONTINUE;

            int64 bytes_diff = pending_current_bytes - last_speed_bytes;
            if (bytes_diff < 0) bytes_diff = 0;

            double bytes_per_sec = ((double) bytes_diff * 1000000.0) / (double) elapsed_us;
            current_speed_str = format_speed((int64) bytes_per_sec);

            if (bytes_per_sec > 1024 && pending_total_bytes > pending_current_bytes) {
                int64 remaining_bytes = pending_total_bytes - pending_current_bytes;
                int remaining_sec = (int) (remaining_bytes / bytes_per_sec);
                current_eta_str = format_eta(remaining_sec);
            } else {
                current_eta_str = "";
            }

            last_speed_time = now;
            last_speed_bytes = pending_current_bytes;

            if (!is_synchronizing) {
                apply_progress(pending_filename, pending_current_bytes, pending_total_bytes);
            }
            return Source.CONTINUE;
        }

        public static string format_speed(int64 bytes_per_sec) {
            if (bytes_per_sec <= 0) return "-- B/s";
            return @"$(GLib.format_size(bytes_per_sec))/s";
        }

        public static string format_eta(int seconds) {
            if (seconds <= 0) return "";
            int h = seconds / 3600;
            int m = (seconds % 3600) / 60;
            int s = seconds % 60;
            if (h > 0) {
                return "%d:%02d:%02d".printf(h, m, s);
            } else {
                return "%02d:%02d".printf(m, s);
            }
        }

        public void set_synchronizing() {
            is_synchronizing = true;
            item_label.label = "Synchronizing to storage device...";
            details_label.label = "Flushing cached write buffers to disk, please wait...";
            progress_bar.fraction = 1.0;
            progress_bar.text = "Syncing...";
            if (sync_pulse_timer_id == 0) {
                sync_pulse_timer_id = Timeout.add(200, () => {
                    if (!is_synchronizing || is_finished) {
                        sync_pulse_timer_id = 0;
                        return Source.REMOVE;
                    }
                    progress_bar.pulse();
                    return Source.CONTINUE;
                });
            }
        }

        public void update_progress(string current_filename, int64 current_bytes, int64 total_bytes) {
            if (is_synchronizing) return;

            pending_filename = current_filename;
            pending_current_bytes = current_bytes;
            pending_total_bytes = total_bytes;

            if (last_speed_time == 0) {
                last_speed_time = GLib.get_monotonic_time();
                last_speed_bytes = current_bytes;
            }

            int64 now = GLib.get_monotonic_time();
            int64 elapsed = now - last_update_time;

            // Throttle UI updates smoothly (at most 10 times per sec, or on initial/completion update)
            if (last_update_time == 0 || elapsed >= 100000 || (total_bytes > 0 && current_bytes >= total_bytes)) {
                if (pending_timeout_id != 0) {
                    Source.remove(pending_timeout_id);
                    pending_timeout_id = 0;
                }
                apply_progress(pending_filename, pending_current_bytes, pending_total_bytes);
                last_update_time = now;
            } else if (pending_timeout_id == 0) {
                uint remaining_ms = (uint) ((100000 - elapsed) / 1000);
                if (remaining_ms < 10) remaining_ms = 10;
                pending_timeout_id = Timeout.add(remaining_ms, () => {
                    pending_timeout_id = 0;
                    apply_progress(pending_filename, pending_current_bytes, pending_total_bytes);
                    last_update_time = GLib.get_monotonic_time();
                    return Source.REMOVE;
                });
            }
        }

        private void apply_progress(string current_filename, int64 current_bytes, int64 total_bytes) {
            if (is_synchronizing) return;

            item_label.label = current_filename;
            if (total_bytes > 0) {
                double frac = (double) current_bytes / (double) total_bytes;
                if (frac > 1.0) frac = 1.0;
                if (frac < 0.0) frac = 0.0;
                progress_bar.fraction = frac;
                progress_bar.text = @"$((int) (frac * 100))%";

                string size_info = @"$(GLib.format_size(current_bytes)) of $(GLib.format_size(total_bytes))";
                string extra = "";
                if (current_speed_str.length > 0) {
                    extra += @" • $current_speed_str";
                }
                if (current_eta_str.length > 0) {
                    extra += @" • ETA: $current_eta_str";
                }
                details_label.label = size_info + extra;

                if (current_bytes >= total_bytes) {
                    set_synchronizing();
                }
            } else {
                progress_bar.pulse();
                string details = current_bytes > 0 ? GLib.format_size(current_bytes) : "";
                if (current_speed_str.length > 0) {
                    details += @" • $current_speed_str";
                }
                details_label.label = details;
            }
        }

        public void update_items_progress(string current_filename, int current_item, int total_items) {
            if (is_synchronizing) return;

            item_label.label = current_filename;
            if (total_items > 0) {
                double frac = (double) current_item / (double) total_items;
                if (frac > 1.0) frac = 1.0;
                if (frac < 0.0) frac = 0.0;
                progress_bar.fraction = frac;
                progress_bar.text = @"$((int) (frac * 100))%";
                details_label.label = @"$current_item of $total_items items";
            }
        }

        public void finish() {
            cleanup_timers();
            is_finished = true;
            force_close();
        }
    }
}
