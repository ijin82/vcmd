namespace VCommander {

    public class RemoteMount : Object {
        public static string build_uri(string scheme, string host, string port, string user, string directory) {
            string clean_host = host.strip();
            string clean_user = user.strip();
            string clean_port = port.strip();
            string clean_dir = directory.strip();
            if (clean_dir.length == 0) {
                clean_dir = "/";
            } else if (!clean_dir.has_prefix("/")) {
                clean_dir = "/" + clean_dir;
            }

            string auth = "";
            if (clean_user.length > 0) {
                auth = Uri.escape_string(clean_user, null, false) + "@";
            }
            string port_part = "";
            if (clean_port.length > 0) {
                port_part = ":" + clean_port;
            }
            return @"$scheme://$auth$clean_host$port_part$clean_dir";
        }

        public static string? discover_agent(int terminal_pid) {
            var candidates = new GenericArray<string>();

            // 1. From terminal environment and its child processes
            if (terminal_pid > 0) {
                string? from_terminal = read_proc_env(terminal_pid, "SSH_AUTH_SOCK");
                if (from_terminal != null && from_terminal.length > 0) {
                    candidates.add(from_terminal);
                }
                scan_proc_children_for_agent(terminal_pid, candidates);
            }

            // 2. Current environment
            string? own = Environment.get_variable("SSH_AUTH_SOCK");
            if (own != null && own.length > 0) {
                candidates.add(own);
            }

            // 3. Scan /proc/net/unix for active agent sockets
            scan_proc_net_unix(candidates);

            // 4. Standard socket locations
            string uid_str = ((uint) Posix.getuid()).to_string();
            candidates.add(@"/run/user/$uid_str/openssh_agent");
            candidates.add(@"/run/user/$uid_str/ssh-agent.socket");
            candidates.add(@"/run/user/$uid_str/keyring/ssh");

            string? user = Environment.get_variable("USER");
            if (user == null || user.length == 0) {
                user = Environment.get_variable("LOGNAME");
            }
            if (user != null && user.length > 0) {
                scan_tmp_agent_sockets(@"/tmp/.private/$user", candidates);
            }
            scan_tmp_agent_sockets("/tmp", candidates);

            // Evaluate candidates: prioritize socket that actually contains loaded keys (> 0)
            string? fallback_socket = null;
            var seen = new GenericSet<string>(str_hash, str_equal);
            for (int i = 0; i < candidates.length; i++) {
                string cand = candidates.get(i);
                if (cand in seen) {
                    continue;
                }
                seen.add(cand);

                int keys = count_agent_keys(cand);
                if (keys > 0) {
                    Environment.set_variable("SSH_AUTH_SOCK", cand, true);
                    return cand;
                } else if (keys == 0 && fallback_socket == null) {
                    fallback_socket = cand;
                }
            }

            if (fallback_socket != null) {
                Environment.set_variable("SSH_AUTH_SOCK", fallback_socket, true);
                return fallback_socket;
            }
            return null;
        }

        public static async File prepare(File file, string? agent_sock, Gtk.Window? parent, Cancellable? cancellable) throws Error {
            string? scheme = file.get_uri_scheme();
            if (scheme == "ssh" || scheme == "sftp") {
                File? mounted = yield try_sshfs(file, agent_sock, cancellable);
                if (mounted != null) {
                    return mounted;
                }
            }
            yield ensure_mounted(file, parent, cancellable);
            return file;
        }

        public static async void ensure_mounted(File file, Gtk.Window? parent, Cancellable? cancellable) throws Error {
            string? scheme = file.get_uri_scheme();
            if (scheme == null || scheme == "file") {
                return;
            }

            try {
                yield file.query_info_async(
                    "standard::type",
                    FileQueryInfoFlags.NONE,
                    Priority.DEFAULT,
                    cancellable
                );
                return;
            } catch (IOError.NOT_MOUNTED e) {
            } catch (IOError.FAILED e) {
            } catch (Error e) {
                if (!(e.message.down().contains("not mounted") || e.message.down().contains("volume"))) {
                    throw e;
                }
            }

            var op = new RemoteMountOperation(parent);
            try {
                yield file.mount_enclosing_volume(MountMountFlags.NONE, op, cancellable);
            } catch (IOError.ALREADY_MOUNTED e) {
            }
        }

        public static int count_agent_keys(string sock_path) {
            if (sock_path.length == 0 || !FileUtils.test(sock_path, FileTest.EXISTS)) {
                return -1;
            }
            try {
                var sock = new Socket(SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT);
                sock.set_timeout(1);
                var addr = new UnixSocketAddress(sock_path);
                sock.connect(addr);

                uint8 req[5] = { 0, 0, 0, 1, 11 };
                sock.send(req);

                uint8 resp[9];
                ssize_t n = sock.receive(resp);
                sock.close();

                if (n < 9) {
                    return -1;
                }
                if (resp[4] != 12) {
                    return -1;
                }

                uint32 count = ((uint32) resp[5] << 24) |
                               ((uint32) resp[6] << 16) |
                               ((uint32) resp[7] << 8)  |
                               ((uint32) resp[8]);
                return (int) count;
            } catch (Error e) {
                return -1;
            }
        }

        private static void scan_proc_net_unix(GenericArray<string> list) {
            try {
                string contents;
                FileUtils.get_contents("/proc/net/unix", out contents);
                string[] lines = contents.split("\n");
                foreach (string line in lines) {
                    string trimmed = line.strip();
                    if (trimmed.contains("agent.") || trimmed.contains("/ssh") || trimmed.contains("openssh")) {
                        string[] parts = trimmed.split(" ");
                        if (parts.length > 0) {
                            string path = parts[parts.length - 1];
                            if (path.has_prefix("/") && FileUtils.test(path, FileTest.EXISTS)) {
                                list.add(path);
                            }
                        }
                    }
                }
            } catch (Error e) {
            }
        }

        private static void scan_tmp_agent_sockets(string base_dir, GenericArray<string> list) {
            try {
                if (!FileUtils.test(base_dir, FileTest.IS_DIR)) {
                    return;
                }
                Dir dir = Dir.open(base_dir);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (name.has_prefix("ssh-")) {
                        string sub = Path.build_filename(base_dir, name);
                        if (FileUtils.test(sub, FileTest.IS_DIR)) {
                            try {
                                Dir sub_dir = Dir.open(sub);
                                string? agent_name = null;
                                while ((agent_name = sub_dir.read_name()) != null) {
                                    if (agent_name.has_prefix("agent.")) {
                                        string sock = Path.build_filename(sub, agent_name);
                                        if (FileUtils.test(sock, FileTest.EXISTS)) {
                                            list.add(sock);
                                        }
                                    }
                                }
                            } catch (Error e) {
                            }
                        }
                    }
                }
            } catch (Error e) {
            }
        }

        private static void scan_proc_children_for_agent(int pid, GenericArray<string> list) {
            try {
                string children_file = @"/proc/$pid/task/$pid/children";
                if (FileUtils.test(children_file, FileTest.EXISTS)) {
                    string contents;
                    FileUtils.get_contents(children_file, out contents);
                    string[] pids = contents.strip().split(" ");
                    foreach (string child_str in pids) {
                        int cpid = int.parse(child_str);
                        if (cpid > 0) {
                            string? sock = read_proc_env(cpid, "SSH_AUTH_SOCK");
                            if (sock != null && sock.length > 0) {
                                list.add(sock);
                            }
                        }
                    }
                }
            } catch (Error e) {
            }
        }

        private static bool agent_usable(string? sock) {
            if (sock == null || sock.length == 0 || !FileUtils.test(sock, FileTest.EXISTS)) {
                return false;
            }
            return count_agent_keys(sock) >= 0;
        }

        private static string? read_proc_env(int pid, string key) {
            if (pid <= 0) {
                return null;
            }
            try {
                uint8[] data;
                string path = @"/proc/$pid/environ";
                if (!FileUtils.test(path, FileTest.EXISTS)) {
                    return null;
                }
                FileUtils.get_data(path, out data);
                string prefix = key + "=";
                var builder = new StringBuilder();
                for (int i = 0; i < data.length; i++) {
                    if (data[i] == 0) {
                        string entry = builder.str;
                        builder.erase(0, -1);
                        if (entry.has_prefix(prefix)) {
                            return entry.substring(prefix.length);
                        }
                    } else {
                        builder.append_c((char) data[i]);
                    }
                }
            } catch (Error e) {
            }
            return null;
        }

        private static async File? try_sshfs(File file, string? agent_sock, Cancellable? cancellable) throws Error {
            if (!agent_usable(agent_sock)) {
                return null;
            }
            if (Environment.find_program_in_path("sshfs") == null) {
                return null;
            }
            if (cancellable != null && cancellable.is_cancelled()) {
                throw new IOError.CANCELLED("Cancelled");
            }

            Uri uri;
            try {
                uri = Uri.parse(file.get_uri(), UriFlags.NONE);
            } catch (Error e) {
                return null;
            }
            string host = uri.get_host() ?? "";
            if (host.length == 0) {
                return null;
            }
            string user = uri.get_user() ?? "";
            int port = uri.get_port();
            string remote_path = uri.get_path();
            if (remote_path == null || remote_path.length == 0) {
                remote_path = "/";
            }

            string label = user.length > 0 ? @"$user@$host" : host;
            if (port > 0) {
                label += @"_$port";
            }
            string mount_root = Path.build_filename(Environment.get_user_cache_dir(), "vcmd", "ssh");
            DirUtils.create_with_parents(mount_root, 0700);
            string mountpoint = Path.build_filename(mount_root, label);
            DirUtils.create_with_parents(mountpoint, 0700);

            if (mount_contains(mountpoint)) {
                return local_target(mountpoint, remote_path);
            } else {
                Posix.system("fusermount -u -z " + mountpoint + " 2>/dev/null");
            }

            string target = user.length > 0 ? @"$user@$host:/" : @"$host:/";
            var argv = new GenericArray<string>();
            argv.add("sshfs");
            if (port > 0) {
                argv.add("-p");
                argv.add(port.to_string());
            }
            argv.add("-o");
            argv.add("IdentityAgent=" + agent_sock);
            argv.add("-o");
            argv.add("StrictHostKeyChecking=accept-new");
            argv.add("-o");
            argv.add("BatchMode=yes");
            argv.add("-o");
            argv.add("reconnect");
            argv.add("-o");
            argv.add("ServerAliveInterval=15");
            argv.add(target);
            argv.add(mountpoint);

            var args = new string[argv.length];
            for (int i = 0; i < argv.length; i++) {
                args[i] = argv.get(i);
            }

            var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE | SubprocessFlags.STDOUT_SILENCE);
            launcher.setenv("SSH_AUTH_SOCK", agent_sock, true);
            try {
                var proc = launcher.spawnv(args);
                yield proc.wait_check_async(cancellable);
                if (proc.get_exit_status() != 0) {
                    return null;
                }
            } catch (Error e) {
                return null;
            }
            return local_target(mountpoint, remote_path);
        }

        private static File local_target(string mountpoint, string remote_path) {
            var root = File.new_for_path(mountpoint);
            string child = remote_path.has_prefix("/") ? remote_path.substring(1) : remote_path;
            if (child.length == 0) {
                return root;
            }
            return root.resolve_relative_path(child);
        }

        private static bool mount_contains(string mountpoint) {
            try {
                string mounts;
                FileUtils.get_contents("/proc/mounts", out mounts);
                string needle = " " + mountpoint + " ";
                if (!mounts.contains(needle)) {
                    return false;
                }
                return FileUtils.test(mountpoint, FileTest.IS_DIR);
            } catch (Error e) {
                return false;
            }
        }
    }

    public class RemoteMountOperation : MountOperation {
        private delegate void ActionCallback();
        private unowned Gtk.Window? parent_window;
        private Adw.Dialog? current_dialog = null;

        public RemoteMountOperation(Gtk.Window? parent) {
            this.parent_window = parent;
            this.password_save = PasswordSave.NEVER;
        }

        public override void ask_password(string message, string default_user, string default_domain, AskPasswordFlags flags) {
            if (current_dialog != null) {
                current_dialog.close();
                current_dialog = null;
            }

            this.password_save = PasswordSave.NEVER;

            var dialog = new Adw.Dialog();
            current_dialog = dialog;
            dialog.title = "Password";
            dialog.content_width = 420;
            dialog.content_height = 280;

            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.show_title = true;
            toolbar.add_top_bar(header);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            box.margin_start = 16;
            box.margin_end = 16;
            box.margin_top = 12;
            box.margin_bottom = 12;

            var info = new Gtk.Label(message);
            info.wrap = true;
            info.xalign = 0;
            box.append(info);

            Gtk.Entry? user_entry = null;
            if ((flags & AskPasswordFlags.NEED_USERNAME) != 0) {
                user_entry = new Gtk.Entry();
                user_entry.placeholder_text = "User";
                user_entry.text = default_user;
                box.append(user_entry);
            }
            Gtk.Entry? domain_entry = null;
            if ((flags & AskPasswordFlags.NEED_DOMAIN) != 0) {
                domain_entry = new Gtk.Entry();
                domain_entry.placeholder_text = "Domain";
                domain_entry.text = default_domain;
                box.append(domain_entry);
            }
            Gtk.PasswordEntry? password_entry = null;
            if ((flags & AskPasswordFlags.NEED_PASSWORD) != 0) {
                password_entry = new Gtk.PasswordEntry();
                password_entry.placeholder_text = "Password";
                box.append(password_entry);
            }

            var note = new Gtk.Label("The password is used for this connection only and is not saved.");
            note.wrap = true;
            note.xalign = 0;
            note.add_css_class("dim-label");
            box.append(note);
            toolbar.set_content(box);

            bool replied = false;
            var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            bottom.margin_start = 12;
            bottom.margin_end = 12;
            bottom.margin_top = 8;
            bottom.margin_bottom = 8;
            var cancel = new Gtk.Button.with_label("Cancel");
            cancel.clicked.connect(() => {
                if (!replied) {
                    replied = true;
                    this.password_save = PasswordSave.NEVER;
                    this.reply(MountOperationResult.ABORTED);
                }
                dialog.close();
            });
            bottom.append(cancel);
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom.append(spacer);
            var ok = new Gtk.Button.with_label("Connect");
            ok.add_css_class("suggested-action");

            ActionCallback submit = () => {
                if (replied) {
                    return;
                }
                replied = true;
                if (user_entry != null) {
                    this.username = user_entry.text;
                }
                if (domain_entry != null) {
                    this.domain = domain_entry.text;
                }
                if (password_entry != null) {
                    this.password = password_entry.text;
                }
                this.password_save = PasswordSave.NEVER;
                this.reply(MountOperationResult.HANDLED);
                dialog.close();
            };

            ok.clicked.connect(() => submit());
            if (user_entry != null) {
                user_entry.activate.connect(() => submit());
            }
            if (domain_entry != null) {
                domain_entry.activate.connect(() => submit());
            }
            if (password_entry != null) {
                password_entry.activate.connect(() => submit());
            }

            bottom.append(ok);
            toolbar.add_bottom_bar(bottom);
            dialog.set_child(toolbar);
            dialog.closed.connect(() => {
                if (!replied) {
                    replied = true;
                    this.password_save = PasswordSave.NEVER;
                    this.reply(MountOperationResult.ABORTED);
                }
                if (current_dialog == dialog) {
                    current_dialog = null;
                }
            });
            dialog.present(parent_window);
            if (password_entry != null) {
                password_entry.grab_focus();
            } else if (user_entry != null) {
                user_entry.grab_focus();
            }
        }

        public override void ask_question(string message, string[] choices) {
            var dialog = new Adw.AlertDialog("Authentication Question", message);
            for (int i = 0; i < choices.length; i++) {
                string id = i.to_string();
                dialog.add_response(id, choices[i]);
            }
            if (choices.length == 0) {
                dialog.add_response("0", "OK");
                dialog.add_response("1", "Cancel");
            }
            dialog.set_default_response("0");
            dialog.set_close_response((choices.length > 1) ? "1" : "0");
            bool replied = false;
            dialog.response.connect((resp) => {
                if (replied) return;
                replied = true;
                int chosen = int.parse(resp);
                this.choice = chosen;
                if (chosen == 0) {
                    this.reply(MountOperationResult.HANDLED);
                } else {
                    this.reply(MountOperationResult.ABORTED);
                }
            });
            dialog.present(parent_window);
        }

        public override void aborted() {
            if (current_dialog != null) {
                current_dialog.close();
                current_dialog = null;
            }
        }
    }
}
