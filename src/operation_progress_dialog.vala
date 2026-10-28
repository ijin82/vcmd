namespace VCommander {

    public class OperationProgressDialog : Gtk.Window {
        private Gtk.Label title_label;
        private Gtk.Label item_label;
        private Gtk.Label details_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.Button cancel_button;
        private Cancellable cancellable;
        private bool is_finished = false;

        public signal void cancelled();

        public OperationProgressDialog(string op_title, Cancellable cancellable) {
            this.cancellable = cancellable;

            set_title(op_title);
            set_default_size(480, 180);
            set_resizable(false);

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
            main_box.margin_start = 20;
            main_box.margin_end = 20;
            main_box.margin_top = 20;
            main_box.margin_bottom = 20;

            title_label = new Gtk.Label(op_title);
            title_label.xalign = 0.0f;
            title_label.add_css_class("title-3");

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
                cancellable.cancel();
                cancelled();
            });
            btn_box.append(cancel_button);

            main_box.append(title_label);
            main_box.append(item_label);
            main_box.append(progress_bar);
            main_box.append(details_label);
            main_box.append(btn_box);

            set_child(main_box);

            close_request.connect(() => {
                if (!is_finished) {
                    cancellable.cancel();
                    cancelled();
                }
                return false;
            });
        }

        public void update_progress(string current_filename, int64 current_bytes, int64 total_bytes) {
            item_label.label = current_filename;
            if (total_bytes > 0) {
                double frac = (double) current_bytes / (double) total_bytes;
                if (frac > 1.0) frac = 1.0;
                if (frac < 0.0) frac = 0.0;
                progress_bar.fraction = frac;
                progress_bar.text = @"$((int) (frac * 100))%";
                details_label.label = @"$(GLib.format_size(current_bytes)) of $(GLib.format_size(total_bytes))";
            } else {
                progress_bar.pulse();
                details_label.label = GLib.format_size(current_bytes);
            }
        }

        public void finish() {
            is_finished = true;
            close();
        }
    }
}
