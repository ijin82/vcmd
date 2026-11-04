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
            if (dest_file.query_exists()) {
                try {
                    dest_file.delete(null);
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
    }
}
