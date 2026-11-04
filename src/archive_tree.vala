namespace VCommander {

    public errordomain ArchivePasswordError {
        REQUIRED,
        INVALID
    }

    public class ArchiveEntry : Object {
        public string full_path { get; construct set; }
        public string raw_entry_path { get; construct set; default = ""; }
        public string name { get; construct set; }
        public bool is_dir { get; construct set; default = false; }
        public int64 size { get; construct set; default = 0; }
        public DateTime? mtime { get; construct set; default = null; }
        public uint32 mode { get; construct set; default = 0; }
        public string owner { get; construct set; default = ""; }
        public string group { get; construct set; default = ""; }
        public bool is_symlink { get; construct set; default = false; }
        public string? symlink_target { get; construct set; default = null; }

        public ArchiveEntry(
            string full_path,
            string name,
            bool is_dir,
            int64 size = 0,
            DateTime? mtime = null,
            uint32 mode = 0,
            string owner = "",
            string group = "",
            bool is_symlink = false,
            string? symlink_target = null,
            string raw_entry_path = ""
        ) {
            Object(
                full_path: full_path,
                raw_entry_path: raw_entry_path,
                name: name,
                is_dir: is_dir,
                size: size,
                mtime: mtime,
                mode: mode,
                owner: owner,
                group: group,
                is_symlink: is_symlink,
                symlink_target: symlink_target
            );
        }
    }

    public class ArchiveTreeNode : Object {
        public string name { get; construct set; }
        public string full_path { get; construct set; }
        public bool is_dir { get; construct set; default = true; }
        public ArchiveEntry? entry { get; construct set; default = null; }
        public GenericArray<ArchiveTreeNode> children;
        public HashTable<string, ArchiveTreeNode> children_by_name;

        public ArchiveTreeNode(string name, string full_path, bool is_dir, ArchiveEntry? entry = null) {
            Object(name: name, full_path: full_path, is_dir: is_dir, entry: entry);
            children = new GenericArray<ArchiveTreeNode>();
            children_by_name = new HashTable<string, ArchiveTreeNode>(str_hash, str_equal);
        }

        public void add_child(ArchiveTreeNode child) {
            if (!children_by_name.contains(child.name)) {
                children_by_name.insert(child.name, child);
                children.add(child);
            } else {
                var existing = children_by_name.lookup(child.name);
                if (existing != null && existing.entry == null && child.entry != null) {
                    existing.entry = child.entry;
                    existing.is_dir = child.is_dir;
                }
            }
        }

        public ArchiveTreeNode? find_child(string child_name) {
            return children_by_name.lookup(child_name);
        }
    }

    public class ArchiveTree : Object {
        public string archive_path { get; construct set; }
        public int64 file_mtime { get; construct set; default = 0; }
        public ArchiveTreeNode root { get; construct set; }

        public ArchiveTree(string archive_path, int64 file_mtime) {
            var root_node = new ArchiveTreeNode("", "", true, null);
            Object(archive_path: archive_path, file_mtime: file_mtime, root: root_node);
        }

        public void add_entry(ArchiveEntry entry) {
            string path = entry.full_path.strip();
            while (path.has_prefix("/")) path = path.substring(1);
            while (path.has_suffix("/")) path = path.substring(0, path.length - 1);
            if (path.length == 0) return;

            string[] parts = path.split("/");
            ArchiveTreeNode current = root;
            string current_path = "";

            for (int i = 0; i < parts.length; i++) {
                string part = parts[i];
                if (part.length == 0 || part == ".") continue;

                current_path = (current_path.length > 0) ? current_path + "/" + part : part;
                bool is_leaf = (i == parts.length - 1);

                var child = current.find_child(part);
                if (child == null) {
                    bool child_is_dir = is_leaf ? entry.is_dir : true;
                    ArchiveEntry? child_entry = is_leaf ? entry : null;
                    child = new ArchiveTreeNode(part, current_path, child_is_dir, child_entry);
                    current.add_child(child);
                } else if (is_leaf && child.entry == null) {
                    child.entry = entry;
                    child.is_dir = entry.is_dir;
                }
                current = child;
            }
        }

        public ArchiveTreeNode? find_node(string inner_path) {
            string path = inner_path.strip();
            while (path.has_prefix("/")) path = path.substring(1);
            while (path.has_suffix("/")) path = path.substring(0, path.length - 1);
            if (path.length == 0) return root;

            string[] parts = path.split("/");
            ArchiveTreeNode current = root;
            for (int i = 0; i < parts.length; i++) {
                string part = parts[i];
                if (part.length == 0 || part == ".") continue;
                var next = current.find_child(part);
                if (next == null) return null;
                current = next;
            }
            return current;
        }
    }

    public class ArchiveTreeService : Object {
        private static HashTable<string, ArchiveTree>? cache = null;
        private static HashTable<string, string>? password_cache = null;

        public static void init() {
            if (cache == null) {
                cache = new HashTable<string, ArchiveTree>(str_hash, str_equal);
            }
            if (password_cache == null) {
                password_cache = new HashTable<string, string>(str_hash, str_equal);
            }
        }

        public static string? get_cached_password(string archive_path) {
            init();
            return password_cache.lookup(archive_path);
        }

        public static void set_cached_password(string archive_path, string password) {
            init();
            password_cache.insert(archive_path, password);
        }

        public static void clear_cached_password(string archive_path) {
            init();
            password_cache.remove(archive_path);
        }

        public static void clear_cache(string? archive_path = null) {
            init();
            if (archive_path != null) {
                cache.remove(archive_path);
                password_cache.remove(archive_path);
            } else {
                cache.remove_all();
                password_cache.remove_all();
            }
        }

        public static bool split_archive_uri(string uri, out string? archive_path, out string? inner_path) {
            archive_path = null;
            inner_path = null;

            if (!uri.has_prefix("archive://")) {
                return false;
            }

            string raw_path = uri.substring(10);
            while (raw_path.has_prefix("/")) raw_path = raw_path.substring(1);
            string? unescaped = Uri.unescape_string(raw_path);
            if (unescaped != null) {
                raw_path = unescaped;
            }

            string[] parts = raw_path.split("/");
            var registry = ArchiverRegistry.get_instance();

            for (int i = parts.length; i > 0; i--) {
                var sb = new StringBuilder();
                for (int j = 0; j < i; j++) {
                    if (parts[j].length == 0) continue;
                    sb.append("/");
                    sb.append(parts[j]);
                }
                string candidate = sb.str;

                if (registry.is_archive_filename(candidate)) {
                    var inner_sb = new StringBuilder();
                    for (int j = i; j < parts.length; j++) {
                        if (parts[j].length == 0) continue;
                        if (inner_sb.len > 0) inner_sb.append("/");
                        inner_sb.append(parts[j]);
                    }
                    archive_path = candidate;
                    inner_path = inner_sb.str;
                    return true;
                }
            }

            return false;
        }

        public static async ArchiveTree get_tree(string archive_path, Cancellable? cancellable = null) throws Error {
            init();

            var file = File.new_for_path(archive_path);
            if (!file.query_exists()) {
                throw new IOError.NOT_FOUND(@"Archive file not found: $archive_path");
            }

            var file_info = yield file.query_info_async(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE, Priority.DEFAULT, cancellable);
            int64 mtime = (int64) file_info.get_attribute_uint64(FileAttribute.TIME_MODIFIED);

            var cached = cache.lookup(archive_path);
            if (cached != null && cached.file_mtime == mtime) {
                return cached;
            }

            var tree = new ArchiveTree(archive_path, mtime);
            yield populate_tree(tree, archive_path, cancellable);

            cache.insert(archive_path, tree);
            return tree;
        }

        private static async void populate_tree(ArchiveTree tree, string archive_path, Cancellable? cancellable) throws Error {
            string lower = archive_path.down();
            var registry = ArchiverRegistry.get_instance();
            string? pwd = get_cached_password(archive_path);
            bool has_pwd = (pwd != null && pwd.length > 0);

            string[] cmd_argv;
            if (lower.has_suffix(".tar") || lower.has_suffix(".tar.gz") || lower.has_suffix(".tgz") ||
                lower.has_suffix(".tar.xz") || lower.has_suffix(".txz") || lower.has_suffix(".tar.zst") ||
                lower.has_suffix(".tar.bz2") || lower.has_suffix(".tbz2")) {
                cmd_argv = new string[] { "tar", "-tvf", archive_path };
            } else if (registry.has_tool("7z") || registry.has_tool("7zz")) {
                string tool = registry.has_tool("7z") ? "7z" : "7zz";
                if (has_pwd) {
                    cmd_argv = new string[] { tool, "l", "-ba", "-bsp0", "-p" + pwd, archive_path };
                } else {
                    cmd_argv = new string[] { tool, "l", "-ba", "-bsp0", "-p-", archive_path };
                }
            } else if (lower.has_suffix(".zip") && registry.has_tool("unzip")) {
                cmd_argv = new string[] { "unzip", "-l", archive_path };
            } else {
                // Check ExtFS helper
                string? helper_name = registry.get_extfs_helper_name_for_filename(archive_path);
                if (helper_name != null) {
                    var h = registry.find_extfs_helper(helper_name);
                    if (h != null) {
                        cmd_argv = new string[] { h.script_path, "list", archive_path };
                    } else {
                        throw new IOError.NOT_SUPPORTED(@"No suitable archiver found to list $(Path.get_basename(archive_path))");
                    }
                } else {
                    throw new IOError.NOT_SUPPORTED(@"Unsupported archive format: $(Path.get_basename(archive_path))");
                }
            }

            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            Subprocess proc = launcher.spawnv(cmd_argv);

            var stdout_stream = new DataInputStream(proc.get_stdout_pipe());

            size_t length;
            while (!cancellable.is_cancelled()) {
                string? line = yield stdout_stream.read_line_utf8_async(Priority.DEFAULT, cancellable, out length);
                if (line == null) break;

                string trimmed = line.strip();
                if (trimmed.length == 0) continue;

                ArchiveEntry? entry = null;
                if (cmd_argv[0] == "tar") {
                    entry = parse_tar_line(trimmed);
                } else if (cmd_argv[0] == "7z" || cmd_argv[0] == "7zz") {
                    entry = parse_7z_line(trimmed);
                } else if (cmd_argv[0] == "unzip") {
                    entry = parse_unzip_line(trimmed);
                } else {
                    entry = parse_extfs_line(trimmed);
                }

                if (entry != null) {
                    tree.add_entry(entry);
                }
            }

            try {
                yield proc.wait_check_async(cancellable);
            } catch (Error e) {
                // Read stderr
                string err_text = "";
                try {
                    var err_stream = new DataInputStream(proc.get_stderr_pipe());
                    size_t len;
                    string? err_line;
                    var err_sb = new StringBuilder();
                    while ((err_line = yield err_stream.read_line_utf8_async(Priority.DEFAULT, null, out len)) != null) {
                        err_sb.append(err_line);
                        err_sb.append("\n");
                    }
                    err_text = err_sb.str;
                } catch (Error ignored) {}

                int exit_code = proc.get_if_exited() ? proc.get_exit_status() : -1;
                string lower_err = err_text.down();
                bool is_pwd_err = lower_err.contains("password") || lower_err.contains("wrong password") ||
                                  lower_err.contains("cannot open encrypted archive") || lower_err.contains("headers error") ||
                                  exit_code == 82 || (!has_pwd && (exit_code == 2 || exit_code == 255));

                if (is_pwd_err && tree.root.children.length == 0) {
                    if (has_pwd) {
                        clear_cached_password(archive_path);
                        throw new ArchivePasswordError.INVALID(@"Incorrect password for $(Path.get_basename(archive_path))");
                    } else {
                        throw new ArchivePasswordError.REQUIRED(@"Password required for $(Path.get_basename(archive_path))");
                    }
                }

                // If nothing was parsed and process returned error, bubble up
                if (tree.root.children.length == 0) {
                    throw e;
                }
            }
        }

        private static ArchiveEntry? parse_tar_line(string line) {
            // e.g.: drwxr-xr-x ijin/ijin 0 2026-11-04 13:05 folder/
            //       -rw-r--r-- ijin/ijin 1234 2026-11-04 13:05 folder/file.txt
            string[] parts = line.split_set(" \t");
            var non_empty = new GenericArray<string>();
            for (int i = 0; i < parts.length; i++) {
                if (parts[i].length > 0) non_empty.add(parts[i]);
            }
            if (non_empty.length < 6) return null;

            string perms = non_empty.get(0);
            bool is_dir = perms.has_prefix("d");
            bool is_symlink = perms.has_prefix("l");

            uint32 mode = 0;
            if (perms.length >= 10) {
                if (perms[1] == 'r') mode |= 0400;
                if (perms[2] == 'w') mode |= 0200;
                if (perms[3] == 'x' || perms[3] == 's') mode |= 0100;
                if (perms[4] == 'r') mode |= 0040;
                if (perms[5] == 'w') mode |= 0020;
                if (perms[6] == 'x' || perms[6] == 's') mode |= 0010;
                if (perms[7] == 'r') mode |= 0004;
                if (perms[8] == 'w') mode |= 0002;
                if (perms[9] == 'x' || perms[9] == 't') mode |= 0001;
            }

            string owner = "";
            string group = "";
            string og = non_empty.get(1);
            int slash = og.index_of_char('/');
            if (slash >= 0) {
                owner = og.substring(0, slash);
                group = og.substring(slash + 1);
            } else {
                owner = og;
            }

            int64 size = 0;
            int64.try_parse(non_empty.get(2), out size);

            DateTime? mtime = null;
            if (non_empty.length >= 5) {
                string date_tok = non_empty.get(3);
                string time_tok = non_empty.get(4);
                string iso = date_tok + "T" + (time_tok.length == 5 ? time_tok + ":00" : time_tok);
                mtime = new DateTime.from_iso8601(iso, null);
            }

            // Path starts at token 5
            var sb = new StringBuilder();
            for (uint i = 5; i < non_empty.length; i++) {
                if (sb.len > 0) sb.append(" ");
                sb.append(non_empty.get(i));
            }
            string raw_path = sb.str.strip();
            string? symlink_target = null;
            if (is_symlink) {
                int arrow = raw_path.index_of(" -> ");
                if (arrow > 0) {
                    symlink_target = raw_path.substring(arrow + 4);
                    raw_path = raw_path.substring(0, arrow).strip();
                }
            }

            string raw_entry_path = raw_path;
            while (raw_path.has_prefix("./")) raw_path = raw_path.substring(2);
            while (raw_path.has_suffix("/")) {
                is_dir = true;
                raw_path = raw_path.substring(0, raw_path.length - 1);
            }
            if (raw_path.length == 0) return null;

            string name = Path.get_basename(raw_path);
            return new ArchiveEntry(raw_path, name, is_dir, size, mtime, mode, owner, group, is_symlink, symlink_target, raw_entry_path);
        }

        private static ArchiveEntry? parse_7z_line(string line) {
            // 2026-11-04 13:06:40 .....           11           11  folder/hello.txt
            if (line.length < 54) return null;

            DateTime? mtime = null;
            if (line[4] == '-' && line[7] == '-') {
                string iso = line.substring(0, 10) + "T" + line.substring(11, 8);
                mtime = new DateTime.from_iso8601(iso, null);
            }

            string attr = line.substring(20, 5);
            bool is_dir = attr.contains("D");

            string size_str = line.substring(26, 12).strip();
            int64 size = 0;
            int64.try_parse(size_str, out size);

            string raw_path = line.substring(53).strip();
            string raw_entry_path = raw_path;
            while (raw_path.has_prefix("./")) raw_path = raw_path.substring(2);
            while (raw_path.has_suffix("/")) {
                is_dir = true;
                raw_path = raw_path.substring(0, raw_path.length - 1);
            }
            if (raw_path.length == 0) return null;

            string name = Path.get_basename(raw_path);
            return new ArchiveEntry(raw_path, name, is_dir, size, mtime, 0, "", "", false, null, raw_entry_path);
        }

        private static ArchiveEntry? parse_unzip_line(string line) {
            // Length  Date  Time  Name
            //     11  2026-11-04 13:06   folder/hello.txt
            if (line.has_prefix("Archive:") || line.has_prefix("---------") || line.contains("files")) return null;

            string[] parts = line.split_set(" \t");
            var non_empty = new GenericArray<string>();
            for (int i = 0; i < parts.length; i++) {
                if (parts[i].length > 0) non_empty.add(parts[i]);
            }
            if (non_empty.length < 4) return null;

            int64 size = 0;
            if (!int64.try_parse(non_empty.get(0), out size)) return null;

            DateTime? mtime = null;
            if (non_empty.length >= 3) {
                string d = non_empty.get(1);
                string t = non_empty.get(2);
                string iso = d + "T" + (t.length == 5 ? t + ":00" : t);
                mtime = new DateTime.from_iso8601(iso, null);
            }

            var sb = new StringBuilder();
            for (uint i = 3; i < non_empty.length; i++) {
                if (sb.len > 0) sb.append(" ");
                sb.append(non_empty.get(i));
            }
            string raw_path = sb.str.strip();
            string raw_entry_path = raw_path;
            bool is_dir = raw_path.has_suffix("/");
            while (raw_path.has_prefix("./")) raw_path = raw_path.substring(2);
            while (raw_path.has_suffix("/")) raw_path = raw_path.substring(0, raw_path.length - 1);
            if (raw_path.length == 0) return null;

            string name = Path.get_basename(raw_path);
            return new ArchiveEntry(raw_path, name, is_dir, size, mtime, 0, "", "", false, null, raw_entry_path);
        }

        private static ArchiveEntry? parse_extfs_line(string line) {
            // Standard modified ls -l output
            return parse_tar_line(line);
        }

        public static GenericArray<FileItem> list_directory(ArchiveTree tree, string inner_path, File current_dir_file) {
            var items = new GenericArray<FileItem>();
            var node = tree.find_node(inner_path);
            if (node == null) return items;

            for (uint i = 0; i < node.children.length; i++) {
                var child = node.children.get(i);
                string child_uri = @"archive://$(tree.archive_path)/$(child.full_path)";
                var child_file = File.new_for_uri(child_uri);

                var entry = child.entry;
                int64 size = (entry != null && !child.is_dir) ? entry.size : 0;
                DateTime? mtime = (entry != null) ? entry.mtime : null;
                uint32 mode = (entry != null) ? entry.mode : 0;
                string owner = (entry != null) ? entry.owner : "";
                string group = (entry != null) ? entry.group : "";
                bool is_symlink = (entry != null) ? entry.is_symlink : false;
                string? symlink_target = (entry != null) ? entry.symlink_target : null;

                Icon item_icon;
                if (child.is_dir) {
                    item_icon = new ThemedIcon("folder-symbolic");
                } else {
                    string? mime = ContentType.guess(child.name, null, null);
                    item_icon = ContentType.get_icon(mime != null ? mime : "application/octet-stream");
                }

                string ftype = "";
                if (child.is_dir) {
                    ftype = "Folder";
                } else {
                    int dot_idx = child.name.last_index_of_char('.');
                    if (dot_idx > 0 && dot_idx < child.name.length - 1) {
                        ftype = child.name.substring(dot_idx + 1).up();
                    } else {
                        ftype = "File";
                    }
                }

                var item = new FileItem.custom(
                    child_file,
                    child.name,
                    child.name,
                    size,
                    mtime,
                    child.is_dir,
                    is_symlink,
                    symlink_target,
                    child.name.has_prefix("."),
                    item_icon,
                    ftype,
                    owner,
                    group,
                    mode
                );

                items.add(item);
            }

            return items;
        }

        public static File get_temp_extracted_file(string archive_path, string inner_path) {
            string cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "vcmd", "preview", Path.get_basename(archive_path));
            string dest_path = Path.build_filename(cache_dir, inner_path);
            return File.new_for_path(dest_path);
        }

        public static async void extract_single_file_to(string archive_path, string inner_path, File dest_file, Cancellable? cancellable = null) throws Error {
            var parent = dest_file.get_parent();
            if (parent != null && !parent.query_exists()) {
                parent.make_directory_with_parents(cancellable);
            }

            string member_path = inner_path;
            init();
            var cached = cache.lookup(archive_path);
            if (cached != null) {
                var node = cached.find_node(inner_path);
                if (node != null && node.entry != null && node.entry.raw_entry_path.length > 0) {
                    member_path = node.entry.raw_entry_path;
                }
            }

            string lower = archive_path.down();
            var registry = ArchiverRegistry.get_instance();
            string? pwd = get_cached_password(archive_path);
            bool has_pwd = (pwd != null && pwd.length > 0);

            string[] cmd_argv;
            bool is_extfs = false;

            if (lower.has_suffix(".tar") || lower.has_suffix(".tar.gz") || lower.has_suffix(".tgz") ||
                lower.has_suffix(".tar.xz") || lower.has_suffix(".txz") || lower.has_suffix(".tar.zst") ||
                lower.has_suffix(".tar.bz2") || lower.has_suffix(".tbz2")) {
                cmd_argv = new string[] { "tar", "-xf", archive_path, "-O", member_path };
            } else if (registry.has_tool("7z") || registry.has_tool("7zz")) {
                string tool = registry.has_tool("7z") ? "7z" : "7zz";
                if (has_pwd) {
                    cmd_argv = new string[] { tool, "e", "-so", "-y", "-p" + pwd, archive_path, member_path };
                } else {
                    cmd_argv = new string[] { tool, "e", "-so", "-y", "-p-", archive_path, member_path };
                }
            } else if (lower.has_suffix(".zip") && registry.has_tool("unzip")) {
                if (has_pwd) {
                    cmd_argv = new string[] { "unzip", "-p", "-P", pwd, archive_path, member_path };
                } else {
                    cmd_argv = new string[] { "unzip", "-p", "-P", "", archive_path, member_path };
                }
            } else {
                string? helper_name = registry.get_extfs_helper_name_for_filename(archive_path);
                if (helper_name != null) {
                    var h = registry.find_extfs_helper(helper_name);
                    if (h != null) {
                        is_extfs = true;
                        cmd_argv = new string[] { h.script_path, "copyout", archive_path, member_path, dest_file.get_path() };
                    } else {
                        throw new IOError.NOT_SUPPORTED(@"No suitable archiver found to extract from $(Path.get_basename(archive_path))");
                    }
                } else {
                    throw new IOError.NOT_SUPPORTED(@"Unsupported archive format: $(Path.get_basename(archive_path))");
                }
            }

            if (is_extfs) {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
                Subprocess proc = launcher.spawnv(cmd_argv);
                try {
                    yield proc.wait_check_async(cancellable);
                } catch (Error e) {
                    if (dest_file.query_exists()) {
                        try { dest_file.delete(); } catch (Error ignored) {}
                    }
                    throw e;
                }
            } else {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                Subprocess proc = launcher.spawnv(cmd_argv);

                var in_stream = proc.get_stdout_pipe();
                var out_stream = yield dest_file.replace_async(null, false, FileCreateFlags.REPLACE_DESTINATION, Priority.DEFAULT, cancellable);

                yield out_stream.splice_async(in_stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET, Priority.DEFAULT, cancellable);

                try {
                    yield proc.wait_check_async(cancellable);
                } catch (Error e) {
                    // Read stderr for error analysis
                    string err_text = "";
                    try {
                        var err_stream = new DataInputStream(proc.get_stderr_pipe());
                        size_t len;
                        string? err_line;
                        var err_sb = new StringBuilder();
                        while ((err_line = yield err_stream.read_line_utf8_async(Priority.DEFAULT, null, out len)) != null) {
                            err_sb.append(err_line);
                            err_sb.append("\n");
                        }
                        err_text = err_sb.str;
                    } catch (Error ignored) {}

                    // Clean up partially written / empty output file
                    if (dest_file.query_exists()) {
                        try { dest_file.delete(); } catch (Error ignored) {}
                    }

                    int exit_code = proc.get_if_exited() ? proc.get_exit_status() : -1;
                    string lower_err = err_text.down();
                    bool is_pwd_err = lower_err.contains("password") || lower_err.contains("wrong password") ||
                                      lower_err.contains("encrypted") || lower_err.contains("break signaled") ||
                                      exit_code == 82 || (!has_pwd && (exit_code == 2 || exit_code == 255));

                    if (is_pwd_err) {
                        if (has_pwd) {
                            clear_cached_password(archive_path);
                            throw new ArchivePasswordError.INVALID(@"Incorrect password for $(Path.get_basename(archive_path))");
                        } else {
                            throw new ArchivePasswordError.REQUIRED(@"Password required for $(Path.get_basename(archive_path))");
                        }
                    }

                    throw e;
                }
            }
        }
    }
}
