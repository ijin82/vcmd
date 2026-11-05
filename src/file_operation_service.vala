namespace VCommander {

    public enum ConflictResolution {
        OVERWRITE,
        OVERWRITE_ALL,
        SKIP,
        SKIP_ALL,
        CANCEL
    }

    public interface ConflictResolver : Object {
        public abstract async ConflictResolution resolve_conflict(File source, File dest);
    }

    public class SimpleConflictResolver : Object, ConflictResolver {
        private ConflictResolution default_resolution;

        public SimpleConflictResolver(ConflictResolution resolution = ConflictResolution.OVERWRITE) {
            this.default_resolution = resolution;
        }

        public async ConflictResolution resolve_conflict(File source, File dest) {
            return default_resolution;
        }
    }

    public class SkippedItem : Object {
        public string path { get; set; }
        public string reason { get; set; }

        public SkippedItem(string path, string reason) {
            this.path = path;
            this.reason = reason;
        }
    }

    public delegate void OperationProgressCallback(string current_file, int64 current_num, int64 total_num);

    public class CopyProgressTracker : Object {
        public int64 total_bytes { get; set; default = 0; }
        public int64 copied_bytes { get; set; default = 0; }
        private GenericArray<SkippedItem>? _skipped_items;

        public GenericArray<SkippedItem> skipped_items {
            get {
                if (_skipped_items == null) {
                    _skipped_items = new GenericArray<SkippedItem>();
                }
                return _skipped_items;
            }
        }

        public void add_skipped_item(string path, string reason) {
            skipped_items.add(new SkippedItem(path, reason));
        }

        public bool has_skipped_items {
            get {
                return _skipped_items != null && _skipped_items.length > 0;
            }
        }
    }

    public class FileOperationService : Object {

        public static string format_error(Error err, string action_desc) {
            if (err.matches(IOError.quark(), IOError.EXISTS)) {
                return @"The destination already exists: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.NOT_FOUND)) {
                return @"File or directory not found: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.PERMISSION_DENIED)) {
                return @"Permission denied: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.NOT_SUPPORTED)) {
                return @"Operation not supported by destination filesystem: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.NOT_EMPTY)) {
                return @"Directory is not empty: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.NO_SPACE)) {
                return @"No space left on target device: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.READ_ONLY)) {
                return @"Destination file system is read-only: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.BUSY)) {
                return @"Resource is busy: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.CANCELLED)) {
                return "Operation was cancelled.";
            }
            return @"Failed to $action_desc: $(err.message)";
        }

        public static async void make_directory(File dir, Cancellable? cancellable = null) throws Error {
            yield dir.make_directory_async(Priority.DEFAULT, cancellable);
        }

        public static async void create_symbolic_link(
            File symlink_file,
            string target_path,
            bool overwrite,
            Cancellable? cancellable = null
        ) throws Error {
            if (overwrite) {
                try {
                    var info = yield symlink_file.query_info_async(
                        FileAttribute.STANDARD_TYPE,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                        Priority.DEFAULT,
                        cancellable
                    );
                    if (info != null) {
                        if (info.get_file_type() == FileType.DIRECTORY) {
                            yield delete_recursive(symlink_file, cancellable);
                        } else {
                            yield symlink_file.delete_async(Priority.DEFAULT, cancellable);
                        }
                    }
                } catch (Error e) {
                    if (!e.matches(IOError.quark(), IOError.NOT_FOUND)) {
                        throw e;
                    }
                }
            }
            yield symlink_file.make_symbolic_link_async(target_path, Priority.DEFAULT, cancellable);
        }

        public static async void trash_file(File file, Cancellable? cancellable = null) throws Error {
            yield file.trash_async(Priority.DEFAULT, cancellable);
        }

        public static async void delete_recursive(File file, Cancellable? cancellable = null) throws Error {
            // Files in trash:/// cannot have individual sub-items modified; deleting the trash item deletes the entry
            if (file.get_uri_scheme() == "trash") {
                yield file.delete_async(Priority.DEFAULT, cancellable);
                return;
            }

            var info = yield file.query_info_async(
                FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                Priority.DEFAULT,
                cancellable
            );

            if (info.get_file_type() == FileType.DIRECTORY) {
                var enumerator = yield file.enumerate_children_async(
                    FileAttribute.STANDARD_NAME,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    Priority.DEFAULT,
                    cancellable
                );

                while (true) {
                    if (cancellable != null && cancellable.is_cancelled()) {
                        throw new IOError.CANCELLED("Operation cancelled");
                    }
                    var file_list = yield enumerator.next_files_async(100, Priority.DEFAULT, cancellable);
                    if (file_list == null || file_list.length() == 0) {
                        break;
                    }
                    foreach (var child_info in file_list) {
                        var child_file = file.get_child(child_info.get_name());
                        yield delete_recursive(child_file, cancellable);
                    }
                }
            }

            yield file.delete_async(Priority.DEFAULT, cancellable);
        }

        public static async bool file_exists_async(File file, Cancellable? cancellable = null) {
            try {
                var info = yield file.query_info_async(
                    FileAttribute.STANDARD_NAME,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    Priority.DEFAULT,
                    cancellable
                );
                return (info != null);
            } catch (Error e) {
                return false;
            }
        }

        public static async void make_directory_with_parents_async(File dir, Cancellable? cancellable = null) throws Error {
            bool exists = yield file_exists_async(dir, cancellable);
            if (exists) return;

            var parent = dir.get_parent();
            if (parent != null) {
                yield make_directory_with_parents_async(parent, cancellable);
            }

            try {
                yield dir.make_directory_async(Priority.DEFAULT, cancellable);
            } catch (Error e) {
                if (!e.matches(IOError.quark(), IOError.EXISTS)) {
                    throw e;
                }
            }
        }

        public static async void restore_trash_file(
            File trash_file,
            string orig_path,
            bool overwrite,
            Cancellable? cancellable = null
        ) throws Error {
            var dest_file = File.new_for_path(orig_path);
            var parent_dir = dest_file.get_parent();
            if (parent_dir != null) {
                try {
                    yield make_directory_with_parents_async(parent_dir, cancellable);
                } catch (Error e) {}
            }

            if (overwrite) {
                bool d_exists = yield file_exists_async(dest_file, cancellable);
                if (d_exists) {
                    try {
                        yield dest_file.delete_async(Priority.DEFAULT, cancellable);
                    } catch (Error e) {
                        yield delete_recursive(dest_file, cancellable);
                    }
                }
            }

            FileCopyFlags flags = FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS;
            if (overwrite) {
                flags |= FileCopyFlags.OVERWRITE;
            }

            try {
                yield trash_file.move_async(dest_file, flags, Priority.DEFAULT, cancellable, null);
            } catch (Error e) {
                if (e.matches(IOError.quark(), IOError.NOT_SUPPORTED) || e.matches(IOError.quark(), IOError.WOULD_RECURSE)) {
                    var resolver = new SimpleConflictResolver(overwrite ? ConflictResolution.OVERWRITE : ConflictResolution.SKIP);
                    yield copy_file_or_dir(trash_file, dest_file, resolver, cancellable);
                    yield trash_file.delete_async(Priority.DEFAULT, cancellable);
                } else {
                    throw e;
                }
            }
        }

        public static async void empty_trash(Cancellable? cancellable = null) throws Error {
            var trash_root = File.new_for_uri("trash:///");
            var enumerator = yield trash_root.enumerate_children_async(
                FileAttribute.STANDARD_NAME,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                Priority.DEFAULT,
                cancellable
            );

            while (true) {
                if (cancellable != null && cancellable.is_cancelled()) {
                    throw new IOError.CANCELLED("Operation cancelled");
                }
                var files = yield enumerator.next_files_async(25, Priority.DEFAULT, cancellable);
                if (files == null || files.length() == 0) {
                    break;
                }
                foreach (var child_info in files) {
                    if (cancellable != null && cancellable.is_cancelled()) {
                        throw new IOError.CANCELLED("Operation cancelled");
                    }
                    var child = trash_root.get_child(child_info.get_name());
                    try {
                        yield child.delete_async(Priority.DEFAULT, cancellable);
                    } catch (Error e) {
                        try {
                            yield delete_recursive(child, cancellable);
                        } catch (Error e2) {}
                    }
                }
            }
        }

        public static async int64 calculate_total_size(File file, Cancellable? cancellable = null) {
            try {
                var info = yield file.query_info_async(
                    FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    Priority.DEFAULT,
                    cancellable
                );
                if (info.get_file_type() == FileType.DIRECTORY) {
                    int64 sum = 0;
                    var enumerator = yield file.enumerate_children_async(
                        FileAttribute.STANDARD_NAME,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                        Priority.DEFAULT,
                        cancellable
                    );
                    while (true) {
                        if (cancellable != null && cancellable.is_cancelled()) return sum;
                        var list = yield enumerator.next_files_async(200, Priority.DEFAULT, cancellable);
                        if (list == null || list.length() == 0) break;
                        foreach (var item in list) {
                            var child = file.get_child(item.get_name());
                            sum += yield calculate_total_size(child, cancellable);
                        }
                    }
                    return sum;
                } else {
                    return info.get_size();
                }
            } catch (Error e) {
                return 0;
            }
        }

        public static async void copy_file_or_dir(
            File source,
            File dest,
            ConflictResolver? resolver = null,
            Cancellable? cancellable = null,
            OperationProgressCallback? progress_cb = null,
            CopyProgressTracker? tracker = null
        ) throws Error {
            var src_info = yield source.query_info_async(
                FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_SIZE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                Priority.DEFAULT,
                cancellable
            );

            if (src_info.get_file_type() == FileType.DIRECTORY) {
                bool dest_exists = yield file_exists_async(dest, cancellable);
                if (!dest_exists) {
                    yield dest.make_directory_async(Priority.DEFAULT, cancellable);
                } else {
                    var dest_info = yield dest.query_info_async(
                        FileAttribute.STANDARD_TYPE,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                        Priority.DEFAULT,
                        cancellable
                    );
                    if (dest_info.get_file_type() != FileType.DIRECTORY) {
                        ConflictResolution decision = ConflictResolution.OVERWRITE;
                        if (resolver != null) {
                            decision = yield resolver.resolve_conflict(source, dest);
                        }
                        if (decision == ConflictResolution.CANCEL) {
                            throw new IOError.CANCELLED("Operation cancelled");
                        } else if (decision == ConflictResolution.SKIP) {
                            if (tracker != null) {
                                tracker.add_skipped_item(source.get_parse_name(), "Skipped (destination file already exists)");
                            }
                            return;
                        } else if (decision == ConflictResolution.OVERWRITE) {
                            yield dest.delete_async(Priority.DEFAULT, cancellable);
                            yield dest.make_directory_async(Priority.DEFAULT, cancellable);
                        }
                    }
                }

                if (progress_cb != null && tracker != null) {
                    progress_cb(source.get_basename(), tracker.copied_bytes, tracker.total_bytes);
                }

                var enumerator = yield source.enumerate_children_async(
                    FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    Priority.DEFAULT,
                    cancellable
                );

                while (true) {
                    if (cancellable != null && cancellable.is_cancelled()) {
                        throw new IOError.CANCELLED("Operation cancelled");
                    }
                    var file_list = yield enumerator.next_files_async(100, Priority.DEFAULT, cancellable);
                    if (file_list == null || file_list.length() == 0) {
                        break;
                    }
                    foreach (var child_info in file_list) {
                        var child_src = source.get_child(child_info.get_name());
                        var child_dest = dest.get_child(child_info.get_name());
                        yield copy_file_or_dir(child_src, child_dest, resolver, cancellable, progress_cb, tracker);
                    }
                }
            } else {
                bool is_symlink = (src_info.get_file_type() == FileType.SYMBOLIC_LINK);
                int64 current_file_bytes_done = 0;
                int64 file_start_copied = (tracker != null) ? tracker.copied_bytes : 0;
                int64 total_bytes = (tracker != null) ? tracker.total_bytes : 0;
                string filename = source.get_basename();

                bool dest_exists = yield file_exists_async(dest, cancellable);
                if (dest_exists) {
                    ConflictResolution decision = ConflictResolution.OVERWRITE;
                    if (resolver != null) {
                        decision = yield resolver.resolve_conflict(source, dest);
                    }
                    if (decision == ConflictResolution.CANCEL) {
                        throw new IOError.CANCELLED("Operation cancelled");
                    } else if (decision == ConflictResolution.SKIP) {
                        if (tracker != null) {
                            tracker.add_skipped_item(source.get_parse_name(), "Skipped (already exists)");
                            tracker.copied_bytes = file_start_copied + src_info.get_size();
                            if (progress_cb != null) {
                                progress_cb(filename, tracker.copied_bytes, total_bytes);
                            }
                        }
                        return;
                    } else if (decision == ConflictResolution.OVERWRITE) {
                        try {
                            yield dest.delete_async(Priority.DEFAULT, cancellable);
                        } catch (Error e) {
                            yield delete_recursive(dest, cancellable);
                        }
                    }
                }

                FileCopyFlags flags = FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS;

                try {
                    yield source.copy_async(dest, flags, Priority.DEFAULT, cancellable, (cur, total) => {
                        current_file_bytes_done = cur;
                        if (progress_cb != null) {
                            int64 current_overall = file_start_copied + current_file_bytes_done;
                            progress_cb(filename, current_overall, total_bytes);
                        }
                    });
                } catch (Error e) {
                    // Clean up incomplete destination file on cancellation or failure asynchronously
                    try {
                        yield dest.delete_async(Priority.DEFAULT, null);
                    } catch (Error ignored) {}

                    if (is_symlink && (e.matches(IOError.quark(), IOError.NOT_SUPPORTED) || (e.message != null && ("symlink" in e.message.down() || "symbolic link" in e.message.down() || "not supported" in e.message.down())))) {
                        AppLogger.warn("FileOperation", @"Skipping unsupported symlink '$(source.get_parse_name())': $(e.message)");
                        if (tracker != null) {
                            tracker.add_skipped_item(source.get_parse_name(), e.message);
                            tracker.copied_bytes = file_start_copied + src_info.get_size();
                            if (progress_cb != null) {
                                progress_cb(filename, tracker.copied_bytes, total_bytes);
                            }
                        }
                        return;
                    }

                    throw e;
                }

                if (tracker != null) {
                    tracker.copied_bytes = file_start_copied + src_info.get_size();
                    if (progress_cb != null) {
                        progress_cb(filename, tracker.copied_bytes, total_bytes);
                    }
                }
            }
        }

        public static async void move_file_or_dir(
            File source,
            File dest,
            ConflictResolver? resolver = null,
            Cancellable? cancellable = null,
            OperationProgressCallback? progress_cb = null,
            CopyProgressTracker? tracker = null
        ) throws Error {
            bool dest_exists = yield file_exists_async(dest, cancellable);
            if (dest_exists) {
                ConflictResolution decision = ConflictResolution.OVERWRITE;
                if (resolver != null) {
                    decision = yield resolver.resolve_conflict(source, dest);
                }
                if (decision == ConflictResolution.CANCEL) {
                    throw new IOError.CANCELLED("Operation cancelled");
                } else if (decision == ConflictResolution.SKIP) {
                    if (tracker != null) {
                        tracker.add_skipped_item(source.get_parse_name(), "Skipped (already exists)");
                    }
                    return;
                } else if (decision == ConflictResolution.OVERWRITE) {
                    try {
                        yield dest.delete_async(Priority.DEFAULT, cancellable);
                    } catch (Error e) {
                        yield delete_recursive(dest, cancellable);
                    }
                }
            }

            FileCopyFlags flags = FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS;

            try {
                int64 file_start = (tracker != null) ? tracker.copied_bytes : 0;
                int64 total_b = (tracker != null) ? tracker.total_bytes : 0;
                string filename = source.get_basename();

                yield source.move_async(dest, flags, Priority.DEFAULT, cancellable, (cur, total) => {
                    if (progress_cb != null) {
                        progress_cb(filename, file_start + cur, total_b > 0 ? total_b : total);
                    }
                });

                if (tracker != null) {
                    try {
                        var info = yield dest.query_info_async(
                            FileAttribute.STANDARD_SIZE,
                            FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                            Priority.DEFAULT,
                            cancellable
                        );
                        tracker.copied_bytes = file_start + info.get_size();
                    } catch (Error e) {}
                }
            } catch (Error e) {
                // If moving across filesystems or not supported directly, fall back to copy + delete
                if (e.matches(IOError.quark(), IOError.NOT_SUPPORTED) || e.matches(IOError.quark(), IOError.WOULD_RECURSE)) {
                    int prev_skipped = (tracker != null) ? (int) tracker.skipped_items.length : 0;
                    yield copy_file_or_dir(source, dest, resolver, cancellable, progress_cb, tracker);
                    int new_skipped = (tracker != null) ? (int) tracker.skipped_items.length : 0;
                    if (new_skipped == prev_skipped) {
                        yield delete_recursive(source, cancellable);
                    } else {
                        AppLogger.warn("FileOperation", @"Move: not deleting source '$(source.get_parse_name())' because some items were skipped");
                    }
                } else {
                    throw e;
                }
            }
        }
    }
}
