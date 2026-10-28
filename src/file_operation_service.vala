namespace VCommander {

    public enum ConflictResolution {
        OVERWRITE,
        SKIP,
        CANCEL
    }

    public delegate void OperationProgressCallback(string current_file, int64 current_num, int64 total_num);

    public class CopyProgressTracker : Object {
        public int64 total_bytes { get; set; default = 0; }
        public int64 copied_bytes { get; set; default = 0; }
    }

    public class FileOperationService : Object {

        public static string format_error(Error err, string action_desc) {
            if (err.matches(IOError.quark(), IOError.EXISTS)) {
                return @"The destination already exists: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.NOT_FOUND)) {
                return @"File or directory not found: $(err.message)";
            } else if (err.matches(IOError.quark(), IOError.PERMISSION_DENIED)) {
                return @"Permission denied: $(err.message)";
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

        public static async void delete_recursive(File file, Cancellable? cancellable = null) throws Error {
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
                    var file_list = yield enumerator.next_files_async(10, Priority.DEFAULT, cancellable);
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
                        var list = yield enumerator.next_files_async(25, Priority.DEFAULT, cancellable);
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
            bool overwrite,
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
                if (!dest.query_exists(cancellable)) {
                    yield dest.make_directory_async(Priority.DEFAULT, cancellable);
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
                    var file_list = yield enumerator.next_files_async(20, Priority.DEFAULT, cancellable);
                    if (file_list == null || file_list.length() == 0) {
                        break;
                    }
                    foreach (var child_info in file_list) {
                        var child_src = source.get_child(child_info.get_name());
                        var child_dest = dest.get_child(child_info.get_name());
                        yield copy_file_or_dir(child_src, child_dest, overwrite, cancellable, progress_cb, tracker);
                    }
                }
            } else {
                FileCopyFlags flags = FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS;
                if (overwrite) {
                    flags |= FileCopyFlags.OVERWRITE;
                }

                int64 current_file_bytes_done = 0;
                int64 file_start_copied = (tracker != null) ? tracker.copied_bytes : 0;
                int64 total_bytes = (tracker != null) ? tracker.total_bytes : 0;
                string filename = source.get_basename();

                yield source.copy_async(dest, flags, Priority.DEFAULT, cancellable, (cur, total) => {
                    current_file_bytes_done = cur;
                    if (progress_cb != null) {
                        int64 current_overall = file_start_copied + current_file_bytes_done;
                        progress_cb(filename, current_overall, total_bytes);
                    }
                });

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
            bool overwrite,
            Cancellable? cancellable = null,
            FileProgressCallback? progress_cb = null
        ) throws Error {
            FileCopyFlags flags = FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS;
            if (overwrite) {
                flags |= FileCopyFlags.OVERWRITE;
            }

            try {
                yield source.move_async(dest, flags, Priority.DEFAULT, cancellable, progress_cb);
            } catch (Error e) {
                // If moving across filesystems or not supported directly, fall back to copy + delete
                if (e.matches(IOError.quark(), IOError.NOT_SUPPORTED) || e.matches(IOError.quark(), IOError.WOULD_RECURSE)) {
                    yield copy_file_or_dir(source, dest, overwrite, cancellable, null, null);
                    yield delete_recursive(source, cancellable);
                } else {
                    throw e;
                }
            }
        }
    }
}
