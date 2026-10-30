namespace VCommander {

    public class ConnectDialog : Object {
        private static ConnectDialog? active = null;

        private unowned Gtk.Window parent_window;
        private unowned FilePanel target_panel;
        private Adw.Dialog dialog;
        private Gtk.DropDown protocol_dropdown;
        private Gtk.Entry host_entry;
        private Gtk.Entry port_entry;
        private Gtk.Entry user_entry;
        private Gtk.Entry directory_entry;
        private Gtk.Entry name_entry;
        private Gtk.Switch remember_switch;
        private Gtk.Label status_label;
        private Gtk.Button connect_button;
        private bool connecting = false;
        private bool closed = false;

        public static void show(Gtk.Window parent, FilePanel target_panel) {
            if (active != null) {
                active.dialog.present(parent);
                return;
            }
            var dlg = new ConnectDialog(parent, target_panel);
            dlg.dialog.present(parent);
            dlg.host_entry.grab_focus();
        }

        private ConnectDialog(Gtk.Window parent, FilePanel target_panel) {
            this.parent_window = parent;
            this.target_panel = target_panel;
            active = this;

            dialog = new Adw.Dialog();
            dialog.title = "Connect to Server";
            dialog.content_width = 520;
            dialog.content_height = 460;

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.show_title = true;
            toolbar.add_top_bar(header);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_start = 16;
            box.margin_end = 16;
            box.margin_top = 12;
            box.margin_bottom = 12;

            var protocol_label = new Gtk.Label("Connection type");
            protocol_label.xalign = 0;
            box.append(protocol_label);

            var protocols = new Gtk.StringList(null);
            protocols.append("SSH");
            protocols.append("SFTP");
            protocols.append("FTP");
            protocols.append("SMB");
            protocol_dropdown = new Gtk.DropDown(protocols, null);
            protocol_dropdown.selected = 0;
            protocol_dropdown.tooltip_text = "SSH and SFTP use a loaded SSH key, or ask for a password";
            box.append(protocol_dropdown);

            host_entry = add_field(box, "Host", "server.example.com");
            port_entry = add_field(box, "Port", "Default if empty (SSH/SFTP 22, FTP 21, SMB 445)");
            user_entry = add_field(box, "User", "Leave empty for anonymous FTP");
            directory_entry = add_field(box, "Directory", "/");
            directory_entry.text = "/";
            name_entry = add_field(box, "Bookmark name", "Saved only if Remember is on");

            var remember_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
            remember_row.margin_top = 4;
            var remember_label = new Gtk.Label("Remember in bookmarks");
            remember_label.xalign = 0;
            remember_label.hexpand = true;
            remember_label.tooltip_text = "Stores the address without a password. Reopen it from Ctrl+\\";
            remember_switch = new Gtk.Switch();
            remember_switch.active = true;
            remember_switch.valign = Gtk.Align.CENTER;
            remember_switch.tooltip_text = remember_label.tooltip_text;
            remember_row.append(remember_label);
            remember_row.append(remember_switch);
            box.append(remember_row);

            status_label = new Gtk.Label("Password is requested by the system. SSH keys are used when they are already available.");
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
            var cancel = new Gtk.Button.with_label("Cancel");
            cancel.clicked.connect(() => dialog.close());
            bottom.append(cancel);
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom.append(spacer);
            connect_button = new Gtk.Button.with_label("Connect");
            connect_button.add_css_class("suggested-action");
            connect_button.clicked.connect(() => connect.begin());
            bottom.append(connect_button);
            toolbar.add_bottom_bar(bottom);
            dialog.set_child(toolbar);

            host_entry.activate.connect(() => connect.begin());
            user_entry.activate.connect(() => connect.begin());
            directory_entry.activate.connect(() => connect.begin());
            name_entry.activate.connect(() => connect.begin());

            dialog.closed.connect(() => {
                closed = true;
                if (active == this) {
                    active = null;
                }
            });
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

        private string selected_scheme() {
            switch (protocol_dropdown.selected) {
                case 0:
                    return "ssh";
                case 1:
                    return "sftp";
                case 2:
                    return "ftp";
                case 3:
                    return "smb";
                default:
                    return "ssh";
            }
        }

        private async void connect() {
            if (connecting || closed) {
                return;
            }
            string host = host_entry.text.strip();
            if (host.length == 0) {
                status_label.label = "Enter a host name";
                return;
            }

            string scheme = selected_scheme();
            string uri = RemoteMount.build_uri(scheme, host, port_entry.text, user_entry.text, directory_entry.text);
            File remote = File.new_for_uri(uri);

            connecting = true;
            connect_button.sensitive = false;
            status_label.label = "Connecting…";
            File opened = remote;
            try {
                string? agent = null;
                var main = parent_window as MainWindow;
                if (main != null) {
                    agent = main.terminal_ssh_agent();
                }
                opened = yield RemoteMount.prepare(remote, agent, parent_window, null);
            } catch (Error e) {
                connecting = false;
                connect_button.sensitive = true;
                if (!closed) {
                    status_label.label = e.message;
                }
                return;
            }
            if (closed) {
                return;
            }

            if (remember_switch.active) {
                string name = name_entry.text.strip();
                if (name.length == 0) {
                    string user = user_entry.text.strip();
                    name = user.length > 0 ? @"$user@$host" : host;
                }
                var config = ConfigManager.get_instance();
                bool already = false;
                for (uint i = 0; i < config.bookmarks.length; i++) {
                    if (config.bookmarks.get(i).uri_or_path == uri) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    config.add_bookmark(name, uri);
                }
            }

            target_panel.load_directory(opened);
            target_panel.grab_focus_to_list();
            dialog.close();
        }
    }
}
