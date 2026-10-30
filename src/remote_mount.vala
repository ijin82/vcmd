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
            string? from_terminal = read_proc_env(terminal_pid, "SSH_AUTH_SOCK");
            if (agent_usable(from_terminal)) {
                return from_terminal;
            }
            string? own = Environment.get_variable("SSH_AUTH_SOCK");
            if (agent_usable(own)) {
                return own;
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

            var op = new MountOperation();
            op.password_save = PasswordSave.NEVER;
            op.ask_password.connect((message, default_user, default_domain, flags) => {
                ask_password_once(op, parent, message, default_user, default_domain, flags);
            });
            yield file.mount_enclosing_volume(MountMountFlags.NONE, op, cancellable);
        }

        private static void ask_password_once(MountOperation op, Gtk.Window? parent, string message, string default_user, string default_domain, AskPasswordFlags flags) {
            op.password_save = PasswordSave.NEVER;

            var dialog = new Adw.Dialog();
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
                    op.password_save = PasswordSave.NEVER;
                    op.reply(MountOperationResult.ABORTED);
                }
                dialog.close();
            });
            bottom.append(cancel);
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom.append(spacer);
            var ok = new Gtk.Button.with_label("Connect");
            ok.add_css_class("suggested-action");
            ok.clicked.connect(() => {
                if (replied) {
                    return;
                }
                replied = true;
                if (user_entry != null) {
                    op.username = user_entry.text;
                }
                if (domain_entry != null) {
                    op.domain = domain_entry.text;
                }
                if (password_entry != null) {
                    op.password = password_entry.text;
                }
                op.password_save = PasswordSave.NEVER;
                op.reply(MountOperationResult.HANDLED);
                dialog.close();
            });
            bottom.append(ok);
            toolbar.add_bottom_bar(bottom);
            dialog.set_child(toolbar);
            dialog.closed.connect(() => {
                if (!replied) {
                    replied = true;
                    op.password_save = PasswordSave.NEVER;
                    op.reply(MountOperationResult.ABORTED);
                }
            });
            dialog.present(parent);
            if (password_entry != null) {
                password_entry.grab_focus();
            }
        }

        private static bool agent_usable(string? sock) {
            return sock != null && sock.length > 0 && FileUtils.test(sock, FileTest.EXISTS);
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
                return mounts.contains(needle);
            } catch (Error e) {
                return false;
            }
        }
    }
}
