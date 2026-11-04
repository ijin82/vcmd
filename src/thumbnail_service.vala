namespace VCommander {

    public class ThumbnailTask : Object {
        public GLib.WeakRef item_ref;
        public string filepath;
        public string cache_path;
        public string tmp_path;

        public ThumbnailTask(FileItem item, string filepath, string cache_path, string tmp_path) {
            this.item_ref = GLib.WeakRef(item);
            this.filepath = filepath;
            this.cache_path = cache_path;
            this.tmp_path = tmp_path;
        }

        public FileItem? get_item() {
            var obj = item_ref.get();
            return (obj != null) ? (FileItem) obj : null;
        }
    }

    public class ThumbnailService : Object {
        [CCode (cname = "malloc_trim", cheader = "malloc.h")]
        public extern static int malloc_trim (size_t pad);

        private static ThreadPool<ThumbnailTask>? worker_pool = null;
        private static string? cache_dir = null;
        private static GenericSet<string>? in_flight_hashes = null;
        private static Mutex mutex;

        public static string get_cache_dir() {
            if (cache_dir == null) {
                cache_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "thumbnails");
                var dir = File.new_for_path(cache_dir);
                if (!dir.query_exists()) {
                    try {
                        dir.make_directory_with_parents(null);
                    } catch (Error e) {
                        warning("Failed to create thumbnail cache dir: %s", e.message);
                    }
                }
            }
            return cache_dir;
        }

        public static bool is_in_thumbnail_cache(string path) {
            string c_dir = get_cache_dir();
            if (path == c_dir || path.has_prefix(c_dir + "/") || path.has_prefix(c_dir + "\\")) {
                return true;
            }
            string fd_cache = Path.build_filename(Environment.get_user_cache_dir(), "thumbnails");
            if (path == fd_cache || path.has_prefix(fd_cache + "/") || path.has_prefix(fd_cache + "\\")) {
                return true;
            }
            return false;
        }

        public static void init() {
            get_cache_dir();
            in_flight_hashes = new GenericSet<string>(str_hash, str_equal);

            // Clean up any lingering temporary files from previous interrupted runs
            try {
                var dir = File.new_for_path(cache_dir);
                var enumerator = dir.enumerate_children("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                FileInfo? info = null;
                while ((info = enumerator.next_file(null)) != null) {
                    string name = info.get_name();
                    if (name.has_prefix(".tmp.")) {
                        var tmp_file = dir.get_child(name);
                        try {
                            tmp_file.delete(null);
                        } catch (Error e) {}
                    }
                }
            } catch (Error e) {
                // Ignore enumeration errors
            }

            // Initialize background worker pool with 4 threads
            try {
                worker_pool = new ThreadPool<ThumbnailTask>.with_owned_data(process_task, 4, false);
            } catch (Error e) {
                warning("Failed to initialize ThumbnailService thread pool: %s", e.message);
            }
        }

        public static bool is_supported_image(string filename) {
            int dot = filename.last_index_of_char('.');
            if (dot < 0 || dot >= filename.length - 1) {
                return false;
            }
            string ext = filename.substring(dot + 1).down();
            return (ext == "jpg" || ext == "jpeg" || ext == "png" || 
                    ext == "gif" || ext == "svg" || ext == "webp" || 
                    ext == "bmp" || ext == "ico" || ext == "tiff" || 
                    ext == "tif" || ext == "jfif");
        }

        public static string compute_cache_key(string path, int64 mtime, int64 size) {
            string raw = @"$path:$mtime:$size";
            return Checksum.compute_for_string(ChecksumType.SHA256, raw);
        }

        public static void request_thumbnail(FileItem item, int max_dimension = 300) {
            if (item.is_dir || item.is_parent_dir || item.is_thumbnail_requested) {
                return;
            }

            string? path = item.file.get_path();
            if (path == null || !is_supported_image(item.name) || item.name.has_prefix(".tmp.")) {
                return;
            }

            // Exclude thumbnail cache directory from recursive thumbnail generation
            if (is_in_thumbnail_cache(path)) {
                item.is_thumbnail_requested = true;
                // If it is already a thumbnail in cache dir, load directly as texture without disk writes
                try {
                    item.thumbnail_paintable = Gdk.Texture.from_file(item.file);
                } catch (Error e) {}
                return;
            }

            item.is_thumbnail_requested = true;

            int64 mtime_val = (item.mtime != null) ? item.mtime.to_unix() : 0;
            string key = compute_cache_key(path, mtime_val, item.size);
            string c_dir = get_cache_dir();
            string cache_file = Path.build_filename(c_dir, @"$key.png");

            // Check if already cached on disk
            var c_f = File.new_for_path(cache_file);
            if (c_f.query_exists()) {
                try {
                    var tex = Gdk.Texture.from_file(c_f);
                    item.thumbnail_paintable = tex;
                    return;
                } catch (Error e) {
                    // Cache file corrupted, fall through to regenerate
                }
            }

            // Check in-flight tasks
            mutex.lock();
            if (in_flight_hashes.contains(key)) {
                mutex.unlock();
                return;
            }
            in_flight_hashes.add(key);
            mutex.unlock();

            string tmp_file = Path.build_filename(c_dir, @".tmp.$key.png");
            var task = new ThumbnailTask(item, path, cache_file, tmp_file);

            if (worker_pool != null) {
                try {
                    worker_pool.add((owned) task);
                } catch (Error e) {
                    mutex.lock();
                    in_flight_hashes.remove(key);
                    mutex.unlock();
                }
            } else {
                mutex.lock();
                in_flight_hashes.remove(key);
                mutex.unlock();
            }
        }

        private static void process_task(owned ThumbnailTask task) {
            string key = Path.get_basename(task.cache_path);
            if (key.has_suffix(".png")) {
                key = key.substring(0, key.length - 4);
            }

            // If item has already been finalized (user navigated away), abort immediately
            var active_item = task.get_item();
            if (active_item == null) {
                mutex.lock();
                in_flight_hashes.remove(key);
                bool is_empty = (in_flight_hashes.length == 0);
                mutex.unlock();
                if (is_empty) {
                    malloc_trim(0);
                }
                return;
            }

            bool success = false;
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale(task.filepath, 300, 300, true);
                if (pixbuf != null) {
                    var oriented = pixbuf.apply_embedded_orientation();
                    var final_pb = (oriented != null) ? oriented : pixbuf;
                    final_pb.save(task.tmp_path, "png");
                    GLib.FileUtils.rename(task.tmp_path, task.cache_path);
                    success = true;
                }
            } catch (Error e) {
                var tmp_f = File.new_for_path(task.tmp_path);
                try {
                    tmp_f.delete(null);
                } catch (Error err) {}
            }

            mutex.lock();
            in_flight_hashes.remove(key);
            bool remaining_empty = (in_flight_hashes.length == 0);
            mutex.unlock();

            if (remaining_empty) {
                malloc_trim(0);
            }

            if (success) {
                Idle.add(() => {
                    var target_item = task.get_item();
                    if (target_item != null) {
                        try {
                            var cache_f = File.new_for_path(task.cache_path);
                            if (cache_f.query_exists()) {
                                var tex = Gdk.Texture.from_file(cache_f);
                                target_item.thumbnail_paintable = tex;
                            }
                        } catch (Error e) {}
                    }
                    return Source.REMOVE;
                });
            }
        }
    }
}
