namespace VCommander {

    public class OperationRow : Gtk.Box {
        public OperationProgressDialog task { get; private set; }
        private Gtk.Label item_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.Label details_label;
        private ulong progress_handler_id = 0;

        public signal void restore_clicked(OperationProgressDialog task);
        public signal void cancel_clicked(OperationProgressDialog task);

        public OperationRow(OperationProgressDialog task) {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.task = task;

            add_css_class("operation-row");

            // Top row: Icon + Title + Action buttons
            var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);

            string icon_name = "folder-download-symbolic";
            string lower_title = task.op_title.down();
            if ("copy" in lower_title) {
                icon_name = "edit-copy-symbolic";
            } else if ("move" in lower_title) {
                icon_name = "folder-download-symbolic";
            } else if ("trash" in lower_title || "restore" in lower_title) {
                icon_name = "user-trash-symbolic";
            } else if ("delete" in lower_title) {
                icon_name = "edit-delete-symbolic";
            } else if ("symlink" in lower_title || "link" in lower_title) {
                icon_name = "insert-link-symbolic";
            }

            var icon_img = new Gtk.Image.from_icon_name(icon_name);
            icon_img.pixel_size = 18;
            icon_img.valign = Gtk.Align.CENTER;
            header_box.append(icon_img);

            var title_label = new Gtk.Label(task.op_title);
            title_label.add_css_class("heading");
            title_label.hexpand = true;
            title_label.halign = Gtk.Align.START;
            title_label.xalign = 0.0f;
            title_label.ellipsize = Pango.EllipsizeMode.END;
            header_box.append(title_label);

            var restore_btn = new Gtk.Button.from_icon_name("view-fullscreen-symbolic");
            restore_btn.add_css_class("flat");
            restore_btn.add_css_class("circular");
            restore_btn.focusable = false;
            restore_btn.valign = Gtk.Align.CENTER;
            restore_btn.tooltip_text = "Restore Progress Dialog";
            restore_btn.clicked.connect(() => {
                restore_clicked(task);
            });
            header_box.append(restore_btn);

            var cancel_btn = new Gtk.Button.from_icon_name("process-stop-symbolic");
            cancel_btn.add_css_class("flat");
            cancel_btn.add_css_class("circular");
            cancel_btn.focusable = false;
            cancel_btn.valign = Gtk.Align.CENTER;
            cancel_btn.tooltip_text = "Cancel Operation";
            cancel_btn.clicked.connect(() => {
                cancel_btn.sensitive = false;
                cancel_clicked(task);
            });
            header_box.append(cancel_btn);

            append(header_box);

            // Item filename label
            item_label = new Gtk.Label(task.current_item_name.length > 0 ? task.current_item_name : "Preparing...");
            item_label.halign = Gtk.Align.START;
            item_label.xalign = 0.0f;
            item_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            item_label.add_css_class("caption");
            item_label.add_css_class("dim-label");
            append(item_label);

            // Progress bar
            progress_bar = new Gtk.ProgressBar();
            progress_bar.fraction = task.current_fraction;
            progress_bar.show_text = true;
            progress_bar.text = @"$((int) (task.current_fraction * 100))%";
            append(progress_bar);

            // Details line (bytes, speed, ETA)
            details_label = new Gtk.Label(task.current_details);
            details_label.halign = Gtk.Align.START;
            details_label.xalign = 0.0f;
            details_label.ellipsize = Pango.EllipsizeMode.END;
            details_label.add_css_class("caption");
            details_label.add_css_class("dim-label");
            append(details_label);

            progress_handler_id = task.progress_updated.connect(update_ui);
            update_ui();
        }

        public void cleanup() {
            if (progress_handler_id != 0) {
                task.disconnect(progress_handler_id);
                progress_handler_id = 0;
            }
        }

        public void update_ui() {
            if (task.is_queued) {
                item_label.label = task.current_item_name;
                progress_bar.fraction = 0.0;
                progress_bar.text = "Queued";
                details_label.label = task.current_details;
            } else if (task.is_synchronizing) {
                item_label.label = "Synchronizing to storage device...";
                progress_bar.fraction = 1.0;
                progress_bar.text = "Syncing...";
                details_label.label = "Flushing cached write buffers to disk, please wait...";
            } else {
                item_label.label = task.current_item_name.length > 0 ? task.current_item_name : "Working...";
                progress_bar.fraction = task.current_fraction;
                progress_bar.text = @"$((int) (task.current_fraction * 100))%";
                details_label.label = task.current_details;
            }
        }
    }

    public class OperationsPopover : Gtk.Popover {
        private Gtk.Box tasks_box;
        private Gtk.Label header_title;
        private GenericArray<OperationRow> rows;

        public signal void restore_requested(OperationProgressDialog task);
        public signal void cancel_requested(OperationProgressDialog task);

        public OperationsPopover() {
            Object();
            rows = new GenericArray<OperationRow>();

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            main_box.set_size_request(380, -1);
            main_box.margin_start = 12;
            main_box.margin_end = 12;
            main_box.margin_top = 10;
            main_box.margin_bottom = 12;

            // Header title
            var header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            header_title = new Gtk.Label("Active Operations");
            header_title.add_css_class("heading");
            header_title.halign = Gtk.Align.START;
            header_box.append(header_title);
            main_box.append(header_box);

            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            main_box.append(sep);

            // Scrolled window for tasks
            var scrolled = new Gtk.ScrolledWindow();
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scrolled.max_content_height = 360;
            scrolled.propagate_natural_height = true;

            tasks_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            scrolled.set_child(tasks_box);
            main_box.append(scrolled);

            set_child(main_box);
        }

        public void add_task(OperationProgressDialog task) {
            // Check if already present
            for (int i = 0; i < rows.length; i++) {
                if (rows[i].task == task) return;
            }

            var row = new OperationRow(task);
            row.restore_clicked.connect((t) => {
                restore_requested(t);
            });
            row.cancel_clicked.connect((t) => {
                cancel_requested(t);
            });

            rows.add(row);
            tasks_box.append(row);
            update_header();
        }

        public void remove_task(OperationProgressDialog task) {
            for (int i = 0; i < rows.length; i++) {
                if (rows[i].task == task) {
                    var r = rows[i];
                    r.cleanup();
                    tasks_box.remove(r);
                    rows.remove_index(i);
                    break;
                }
            }
            update_header();
        }

        public bool has_tasks() {
            return rows.length > 0;
        }

        public int task_count {
            get { return rows.length; }
        }

        private void update_header() {
            if (rows.length <= 1) {
                header_title.label = "Active Operations";
            } else {
                header_title.label = @"Active Operations ($(rows.length))";
            }
        }
    }
}
