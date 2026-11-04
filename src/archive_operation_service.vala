namespace VCommander {

    public class ArchiveOperationService : Object {

        public static async void pack_archive(
            ArchivePackRequest request,
            OperationProgressDialog dlg,
            Cancellable cancellable
        ) throws Error {
            if (request.source_items.length == 0) {
                throw new IOError.INVALID_ARGUMENT("No source files specified for archive.");
            }

            File dest_file = request.destination_archive;
            string? dest_path = dest_file.get_path();
            if (dest_path == null) {
                throw new IOError.NOT_SUPPORTED("Creating archives on virtual/remote paths without local mount is not supported.");
            }

            File? parent_dir = request.source_items.get(0).file.get_parent();
            string? working_dir = (parent_dir != null) ? parent_dir.get_path() : null;
            if (working_dir == null) {
                throw new IOError.NOT_SUPPORTED("Source directory must be a local filesystem path.");
            }

            // Remove existing destination file if overwriting
            bool dest_exists = yield FileOperationService.file_exists_async(dest_file, cancellable);
            if (dest_exists) {
                try {
                    yield dest_file.delete_async(Priority.DEFAULT, cancellable);
                } catch (Error e) {
                    AppLogger.warn("Archive", @"Failed to remove existing destination archive before pack: $(e.message)");
                }
            }

            // Calculate total source size for accurate progress tracking
            int64 total_source_size = 0;
            dlg.update_progress("Calculating source size...", 0, 0);
            for (uint i = 0; i < request.source_items.length; i++) {
                if (cancellable.is_cancelled()) {
                    throw new IOError.CANCELLED("Operation cancelled");
                }
                total_source_size += yield FileOperationService.calculate_total_size(request.source_items.get(i).file, cancellable);
            }
            if (total_source_size <= 0) {
                total_source_size = 1024; // Nominal minimum to avoid zero division
            }

            dlg.update_progress("Starting archiver...", 0, total_source_size);

            // Build CLI command
            var cmd_args = build_pack_command(request, dest_path);

            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            launcher.set_cwd(working_dir);

            string[] argv = new string[cmd_args.length];
            for (uint i = 0; i < cmd_args.length; i++) {
                argv[i] = cmd_args.get(i);
            }

            AppLogger.info("Archive", @"Spawning archiver: $(argv[0]) in $(working_dir)");

            Subprocess proc;
            try {
                proc = launcher.spawnv(argv);
            } catch (Error e) {
                throw new IOError.FAILED(@"Failed to start archiver '$(argv[0])': $(e.message)");
            }

            // Cancellation listener to terminate subprocess
            ulong cancel_handler_id = 0;
            if (cancellable != null) {
                cancel_handler_id = cancellable.connect(() => {
                    AppLogger.info("Archive", "Cancellation requested, terminating archiver subprocess...");
                    proc.force_exit();
                });
            }

            var stdout_stream = new DataInputStream(proc.get_stdout_pipe());
            var stderr_stream = new DataInputStream(proc.get_stderr_pipe());

            var stderr_builder = new StringBuilder();

            // Background stdout & stderr readers
            drain_stdout_stream.begin(stdout_stream, dest_file, dlg, total_source_size, cancellable);
            drain_stderr_stream.begin(stderr_stream, stderr_builder, cancellable);

            // Wait for subprocess completion
            Error? proc_error = null;
            try {
                yield proc.wait_check_async(cancellable);
            } catch (Error e) {
                proc_error = e;
            }

            if (cancel_handler_id != 0 && cancellable != null) {
                cancellable.disconnect(cancel_handler_id);
            }

            if (cancellable.is_cancelled()) {
                // Clean up incomplete/corrupted partial archive
                cleanup_partial_archive(dest_file);
                throw new IOError.CANCELLED("Archive creation cancelled by user");
            }

            if (proc_error != null) {
                cleanup_partial_archive(dest_file);
                string err_text = stderr_builder.str.strip();
                if (err_text.length > 0) {
                    throw new IOError.FAILED(@"Archiver error:\n$err_text");
                } else {
                    throw new IOError.FAILED(@"Archiver process exited with error: $(proc_error.message)");
                }
            }

            // Check if archive was indeed produced
            if (!dest_file.query_exists()) {
                throw new IOError.FAILED("Archiver completed, but destination file was not found.");
            }

            dlg.update_progress("Finalizing archive...", total_source_size, total_source_size);

            // Handle "Delete source files after archiving" (Move to archive)
            if (request.delete_source_after_pack) {
                dlg.update_progress("Removing source files...", total_source_size, total_source_size);
                for (uint i = 0; i < request.source_items.length; i++) {
                    if (cancellable.is_cancelled()) break;
                    var item = request.source_items.get(i);
                    try {
                        yield FileOperationService.delete_recursive(item.file, cancellable);
                    } catch (Error e) {
                        AppLogger.warn("Archive", @"Failed to delete source item '$(item.name)': $(e.message)");
                    }
                }
            }
        }

        private static GenericArray<string> build_pack_command(ArchivePackRequest request, string dest_path) {
            var args = new GenericArray<string>();
            string fmt_id = request.format.id;
            string? pwd = request.password;
            int level = (int) request.compression_level;
            if (level > 9) level = 9;

            if (fmt_id == "zip") {
                if (request.format.default_tool == "zip") {
                    args.add("zip");
                    args.add("-r");
                    args.add(@"-$level");
                    if (pwd != null && pwd.length > 0) {
                        args.add("-P");
                        args.add(pwd);
                    }
                    args.add(dest_path);
                } else {
                    // Use 7z or 7zz for zip
                    string tool = request.format.default_tool.length > 0 ? request.format.default_tool : "7z";
                    args.add(tool);
                    args.add("a");
                    args.add("-tzip");
                    args.add(@"-mx=$level");
                    if (pwd != null && pwd.length > 0) {
                        args.add(@"-p$pwd");
                    }
                    args.add(dest_path);
                }
            } else if (fmt_id == "7z") {
                string tool = request.format.default_tool.length > 0 ? request.format.default_tool : "7z";
                args.add(tool);
                args.add("a");
                args.add(@"-mx=$level");
                if (pwd != null && pwd.length > 0) {
                    args.add(@"-p$pwd");
                    args.add("-mhe=on"); // Encrypt archive header / filenames
                }
                args.add(dest_path);
            } else if (fmt_id.has_prefix("tar")) {
                args.add("tar");
                args.add("-v"); // Verbose output to track progress per item

                if (fmt_id == "tar.gz") {
                    args.add("-I");
                    args.add(@"gzip -$level");
                } else if (fmt_id == "tar.xz") {
                    args.add("-I");
                    args.add(@"xz -$level");
                } else if (fmt_id == "tar.zst") {
                    int zstd_lvl = (level == 0) ? 1 : level;
                    args.add("-I");
                    args.add(@"zstd -$zstd_lvl");
                } else if (fmt_id == "tar.bz2") {
                    args.add("-I");
                    args.add(@"bzip2 -$level");
                }
                // plain "tar" needs no -I flag

                args.add("-cf");
                args.add(dest_path);
            } else {
                // Fallback to tar --auto-compress
                args.add("tar");
                args.add("-v");
                args.add("-caf");
                args.add(dest_path);
            }

            // Append item filenames relative to working directory
            for (uint i = 0; i < request.source_items.length; i++) {
                args.add(request.source_items.get(i).name);
            }

            return args;
        }

        private static async void drain_stdout_stream(
            DataInputStream stream,
            File dest_file,
            OperationProgressDialog dlg,
            int64 total_source_size,
            Cancellable cancellable
        ) {
            int64 last_size_check = 0;
            int64 current_archive_size = 0;

            try {
                size_t length;
                while (!cancellable.is_cancelled()) {
                    string? raw_line = yield stream.read_line_utf8_async(Priority.DEFAULT, cancellable, out length);
                    if (raw_line == null) break;

                    string line = raw_line.strip();
                    if (line.length == 0) continue;

                    string item_name = parse_progress_item_name(line);

                    // Periodically check output archive size on disk
                    int64 now = GLib.get_monotonic_time();
                    if (now - last_size_check > 500000) { // every 500ms
                        last_size_check = now;
                        try {
                            var info = yield dest_file.query_info_async("standard::size", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
                            current_archive_size = info.get_size();
                        } catch (Error e) {}
                    }

                    dlg.update_progress(item_name, current_archive_size, total_source_size);
                }
            } catch (Error e) {
                // Stream finished or cancelled
            }
        }

        private static async void drain_stderr_stream(
            DataInputStream stream,
            StringBuilder builder,
            Cancellable cancellable
        ) {
            try {
                size_t length;
                while (!cancellable.is_cancelled()) {
                    string? line = yield stream.read_line_utf8_async(Priority.DEFAULT, cancellable, out length);
                    if (line == null) break;
                    if (builder.len < 4096) {
                        builder.append(line);
                        builder.append("\n");
                    }
                }
            } catch (Error e) {
                // Stream finished or cancelled
            }
        }

        private static string parse_progress_item_name(string raw_line) {
            // zip: "  adding: folder/file.txt (deflated 65%)"
            if (raw_line.has_prefix("adding: ")) {
                string trimmed = raw_line.substring(8).strip();
                int paren = trimmed.index_of_char('(');
                if (paren > 0) {
                    return trimmed.substring(0, paren).strip();
                }
                return trimmed;
            }

            // 7z: "Compressing  file.txt"
            if (raw_line.has_prefix("Compressing  ")) {
                return raw_line.substring(13).strip();
            }

            // tar -v: just filename e.g. "my_folder/file.txt"
            return raw_line;
        }

        private static void cleanup_partial_archive(File file) {
            try {
                if (file.query_exists()) {
                    file.delete(null);
                }
            } catch (Error e) {
                AppLogger.warn("Archive", @"Failed to clean up partial archive: $(e.message)");
            }
        }

        public static async void update_archive_member(
            string archive_path,
            string inner_path,
            File temp_file,
            Cancellable? cancellable = null
        ) throws Error {
            var registry = ArchiverRegistry.get_instance();
            string lower = archive_path.down();

            // 1. ExtFS archives
            var helper = registry.get_extfs_helper_for_archive(archive_path);
            if (helper != null && !lower.has_suffix(".tar") && !lower.has_suffix(".tar.gz") &&
                !lower.has_suffix(".tgz") && !lower.has_suffix(".tar.xz") && !lower.has_suffix(".txz") &&
                !lower.has_suffix(".tar.zst") && !lower.has_suffix(".tar.bz2") && !lower.has_suffix(".tbz2") &&
                !((lower.has_suffix(".zip") || lower.has_suffix(".7z")) && (registry.has_tool("7z") || registry.has_tool("7zz") || registry.has_tool("zip")))) {
                var runner = ExtFSRunner.get_instance();
                yield runner.copyin(helper, archive_path, inner_path, temp_file.get_path(), cancellable);
                return;
            }

            string cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "vcmd", "preview", Path.get_basename(archive_path));
            string? pwd = ArchiveTreeService.get_cached_password(archive_path);
            bool has_pwd = (pwd != null && pwd.length > 0);

            // 2. ZIP archives
            if (lower.has_suffix(".zip")) {
                if (registry.has_tool("zip")) {
                    var args = new GenericArray<string>();
                    args.add("zip");
                    if (has_pwd) {
                        args.add("-P");
                        args.add(pwd);
                    }
                    args.add(archive_path);
                    args.add(inner_path);
                    string[] argv = new string[args.length];
                    for (int i = 0; i < args.length; i++) argv[i] = args[i];

                    var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
                    launcher.set_cwd(cache_dir);
                    var proc = launcher.spawnv(argv);
                    yield proc.wait_check_async(cancellable);
                    return;
                } else if (registry.has_tool("7z") || registry.has_tool("7zz")) {
                    string tool = registry.has_tool("7z") ? "7z" : "7zz";
                    var args = new GenericArray<string>();
                    args.add(tool);
                    args.add("u");
                    if (has_pwd) {
                        args.add(@"-p$pwd");
                    }
                    args.add(archive_path);
                    args.add(inner_path);
                    string[] argv = new string[args.length];
                    for (int i = 0; i < args.length; i++) argv[i] = args[i];

                    var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
                    launcher.set_cwd(cache_dir);
                    var proc = launcher.spawnv(argv);
                    yield proc.wait_check_async(cancellable);
                    return;
                }
            }

            // 3. 7z archives
            if (lower.has_suffix(".7z")) {
                if (registry.has_tool("7z") || registry.has_tool("7zz")) {
                    string tool = registry.has_tool("7z") ? "7z" : "7zz";
                    var args = new GenericArray<string>();
                    args.add(tool);
                    args.add("u");
                    if (has_pwd) {
                        args.add(@"-p$pwd");
                    }
                    args.add(archive_path);
                    args.add(inner_path);
                    string[] argv = new string[args.length];
                    for (int i = 0; i < args.length; i++) argv[i] = args[i];

                    var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
                    launcher.set_cwd(cache_dir);
                    var proc = launcher.spawnv(argv);
                    yield proc.wait_check_async(cancellable);
                    return;
                }
            }

            // 4. Uncompressed TAR archives
            if (lower.has_suffix(".tar") && registry.has_tool("tar")) {
                string[] argv = { "tar", "-uf", archive_path, inner_path };
                var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
                launcher.set_cwd(cache_dir);
                var proc = launcher.spawnv(argv);
                yield proc.wait_check_async(cancellable);
                return;
            }

            throw new IOError.NOT_SUPPORTED(@"Updating files inside $(Path.get_basename(archive_path)) is not supported for this archive format.");
        }

        public static async void extract_vfs_items(
            string archive_path,
            GenericArray<FileItem> items,
            File dest_dir,
            OperationProgressDialog dlg,
            Cancellable cancellable
        ) throws Error {
            try {
                yield FileOperationService.make_directory_with_parents_async(dest_dir, cancellable);
            } catch (Error e) {}

            var tree = yield ArchiveTreeService.get_tree(archive_path, cancellable);
            var targets = new GenericArray<VfsExtractionTarget>();
            int64 total_size = 0;

            for (uint i = 0; i < items.length; i++) {
                var item = items.get(i);
                string? arc_p, in_p;
                if (!ArchiveTreeService.split_archive_uri(item.file.get_uri(), out arc_p, out in_p)) continue;
                if (in_p == null) continue;

                if (!item.is_dir) {
                    File target_file = dest_dir.get_child(item.name);
                    targets.add(new VfsExtractionTarget(in_p, target_file, item.size));
                    total_size += item.size;
                } else {
                    var node = tree.find_node(in_p);
                    if (node != null) {
                        File child_dest_dir = dest_dir.get_child(item.name);
                        collect_node_leaves(node, in_p, child_dest_dir, targets, ref total_size);
                    }
                }
            }

            if (total_size <= 0) total_size = 1024;
            int64 bytes_extracted = 0;

            for (uint i = 0; i < targets.length; i++) {
                if (cancellable.is_cancelled()) {
                    throw new IOError.CANCELLED("Extraction cancelled");
                }

                var target = targets.get(i);
                dlg.update_progress(target.dest_file.get_basename(), bytes_extracted, total_size);
                yield ArchiveTreeService.extract_single_file_to(archive_path, target.inner_path, target.dest_file, cancellable);
                bytes_extracted += target.size;
                dlg.update_progress(target.dest_file.get_basename(), bytes_extracted, total_size);
            }

            dlg.update_progress("Extraction complete", total_size, total_size);
        }

        private static void collect_node_leaves(
            ArchiveTreeNode node,
            string base_inner_path,
            File base_dest_dir,
            GenericArray<VfsExtractionTarget> targets,
            ref int64 total_size
        ) {
            for (uint i = 0; i < node.children.length; i++) {
                var child = node.children.get(i);
                if (child.is_dir) {
                    collect_node_leaves(child, base_inner_path, base_dest_dir, targets, ref total_size);
                } else {
                    string rel = child.full_path;
                    if (rel.has_prefix(base_inner_path)) {
                        rel = rel.substring(base_inner_path.length);
                    }
                    while (rel.has_prefix("/")) rel = rel.substring(1);

                    File dest_file = (rel.length > 0) ? base_dest_dir.resolve_relative_path(rel) : base_dest_dir.get_child(child.name);
                    int64 sz = (child.entry != null) ? child.entry.size : 0;
                    targets.add(new VfsExtractionTarget(child.full_path, dest_file, sz));
                    total_size += sz;
                }
            }
        }

        public static async void extract_full_archive(
            File archive_file,
            File dest_dir,
            OperationProgressDialog dlg,
            Cancellable cancellable
        ) throws Error {
            try {
                yield FileOperationService.make_directory_with_parents_async(dest_dir, cancellable);
            } catch (Error e) {}

            string? archive_path = archive_file.get_path();
            if (archive_path == null) {
                throw new IOError.NOT_SUPPORTED("Archive file must be on local filesystem.");
            }
            string? dest_path = dest_dir.get_path();
            if (dest_path == null) {
                throw new IOError.NOT_SUPPORTED("Destination folder must be on local filesystem.");
            }

            string lower = archive_path.down();
            var registry = ArchiverRegistry.get_instance();
            string? pwd = ArchiveTreeService.get_cached_password(archive_path);
            bool has_pwd = (pwd != null && pwd.length > 0);

            dlg.update_progress(@"Unpacking $(archive_file.get_basename())...", 0, 0);

            string[] cmd_argv;
            bool is_bulk_cli = false;

            if (lower.has_suffix(".tar") || lower.has_suffix(".tar.gz") || lower.has_suffix(".tgz") ||
                lower.has_suffix(".tar.xz") || lower.has_suffix(".txz") || lower.has_suffix(".tar.zst") ||
                lower.has_suffix(".tar.bz2") || lower.has_suffix(".tbz2")) {
                is_bulk_cli = true;
                cmd_argv = new string[] { "tar", "-xf", archive_path, "-C", dest_path };
            } else if (lower.has_suffix(".zip") && registry.has_tool("unzip")) {
                is_bulk_cli = true;
                if (has_pwd) {
                    cmd_argv = new string[] { "unzip", "-q", "-o", "-P", pwd, archive_path, "-d", dest_path };
                } else {
                    cmd_argv = new string[] { "unzip", "-q", "-o", "-P", "", archive_path, "-d", dest_path };
                }
            } else if ((lower.has_suffix(".7z") || lower.has_suffix(".zip")) && (registry.has_tool("7z") || registry.has_tool("7zz"))) {
                is_bulk_cli = true;
                string tool = registry.has_tool("7z") ? "7z" : "7zz";
                if (has_pwd) {
                    cmd_argv = new string[] { tool, "x", "-y", "-p" + pwd, @"-o$dest_path", archive_path };
                } else {
                    cmd_argv = new string[] { tool, "x", "-y", "-p-", @"-o$dest_path", archive_path };
                }
            } else {
                // ExtFS or unsupported bulk CLI: stream through ArchiveTreeService
                var tree = yield ArchiveTreeService.get_tree(archive_path, cancellable);
                var vfs_items = new GenericArray<FileItem>();
                for (uint i = 0; i < tree.root.children.length; i++) {
                    var ch = tree.root.children.get(i);
                    string uri = @"archive://$archive_path/$(ch.full_path)";
                    var fi = new FileItem.custom(
                        File.new_for_uri(uri),
                        ch.name,
                        ch.name,
                        (ch.entry != null) ? ch.entry.size : 0,
                        (ch.entry != null) ? ch.entry.mtime : null,
                        ch.is_dir,
                        false,
                        null,
                        false,
                        new ThemedIcon(ch.is_dir ? "folder-symbolic" : "text-x-generic-symbolic"),
                        ch.is_dir ? "Folder" : "File",
                        "",
                        "",
                        0
                    );
                    vfs_items.add(fi);
                }
                yield extract_vfs_items(archive_path, vfs_items, dest_dir, dlg, cancellable);
                return;
            }

            if (is_bulk_cli) {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
                Subprocess proc = launcher.spawnv(cmd_argv);

                ulong cancel_handler_id = 0;
                if (cancellable != null) {
                    cancel_handler_id = cancellable.connect(() => {
                        proc.force_exit();
                    });
                }

                var err_stream = new DataInputStream(proc.get_stderr_pipe());
                var err_sb = new StringBuilder();

                Error? proc_error = null;
                try {
                    yield proc.wait_check_async(cancellable);
                } catch (Error e) {
                    proc_error = e;
                }

                if (cancel_handler_id != 0 && cancellable != null) {
                    cancellable.disconnect(cancel_handler_id);
                }

                if (cancellable.is_cancelled()) {
                    throw new IOError.CANCELLED("Archive extraction cancelled by user");
                }

                if (proc_error != null) {
                    size_t len;
                    string? err_line;
                    try {
                        while ((err_line = yield err_stream.read_line_utf8_async(Priority.DEFAULT, null, out len)) != null) {
                            err_sb.append(err_line);
                            err_sb.append("\n");
                        }
                    } catch (Error ignored) {}

                    int exit_code = proc.get_if_exited() ? proc.get_exit_status() : -1;
                    string lower_err = err_sb.str.down();
                    bool is_pwd_err = lower_err.contains("password") || lower_err.contains("wrong password") ||
                                      lower_err.contains("encrypted") || lower_err.contains("break signaled") ||
                                      exit_code == 82 || (!has_pwd && (exit_code == 2 || exit_code == 255));

                    if (is_pwd_err) {
                        if (has_pwd) {
                            ArchiveTreeService.clear_cached_password(archive_path);
                            throw new ArchivePasswordError.INVALID(@"Incorrect password for $(archive_file.get_basename())");
                        } else {
                            throw new ArchivePasswordError.REQUIRED(@"Password required for $(archive_file.get_basename())");
                        }
                    }

                    string err_msg = err_sb.str.strip();
                    if (err_msg.length > 0) {
                        throw new IOError.FAILED(@"Failed to extract $(archive_file.get_basename()):\n$err_msg");
                    } else {
                        throw new IOError.FAILED(@"Failed to extract $(archive_file.get_basename()) (exit code $exit_code)");
                    }
                }
            }

            dlg.update_progress("Extraction complete", 1, 1);
        }
    }

    public class VfsExtractionTarget : Object {
        public string inner_path { get; construct set; }
        public File dest_file { get; construct set; }
        public int64 size { get; construct set; }

        public VfsExtractionTarget(string inner_path, File dest_file, int64 size) {
            Object(inner_path: inner_path, dest_file: dest_file, size: size);
        }
    }
}
