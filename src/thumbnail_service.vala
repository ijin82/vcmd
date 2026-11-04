namespace VCommander {

    public class ThumbnailTask : Object {
        public GLib.WeakRef item_ref;
        public string filepath;
        public string cache_path;
        public string tmp_path;
        public string key;
        public bool is_cancelled;

        public ThumbnailTask(FileItem item, string filepath, string cache_path, string tmp_path, string key) {
            this.item_ref = GLib.WeakRef(item);
            this.filepath = filepath;
            this.cache_path = cache_path;
            this.tmp_path = tmp_path;
            this.key = key;
            this.is_cancelled = false;
        }

        public FileItem? get_item() {
            var obj = item_ref.get();
            return (obj != null) ? (FileItem) obj : null;
        }
    }

    public class ReadyThumbnail : Object {
        public GLib.WeakRef item_ref;
        public Gdk.Texture texture;

        public ReadyThumbnail(FileItem item, Gdk.Texture texture) {
            this.item_ref = GLib.WeakRef(item);
            this.texture = texture;
        }

        public FileItem? get_item() {
            var obj = item_ref.get();
            return (obj != null) ? (FileItem) obj : null;
        }
    }

    public class LruTextureCache {
        private int max_entries;
        private GLib.HashTable<string, Gdk.Texture> map;
        private GLib.Queue<string> order;
        private GLib.Mutex mutex;

        public LruTextureCache(int max_entries = 300) {
            this.max_entries = max_entries;
            this.map = new GLib.HashTable<string, Gdk.Texture>(GLib.str_hash, GLib.str_equal);
            this.order = new GLib.Queue<string>();
        }

        public Gdk.Texture? get(string key) {
            mutex.lock();
            var tex = map.lookup(key);
            mutex.unlock();
            return tex;
        }

        public void put(string key, Gdk.Texture tex) {
            mutex.lock();
            if (!map.contains(key)) {
                while ((int)order.get_length() >= max_entries) {
                    string? oldest = order.pop_head();
                    if (oldest != null) {
                        map.remove(oldest);
                    }
                }
                order.push_tail(key);
            }
            map.insert(key, tex);
            mutex.unlock();
        }

        public void clear() {
            mutex.lock();
            map.remove_all();
            order.clear();
            mutex.unlock();
        }
    }

    public class ThumbnailService : Object {
        [CCode (cname = "malloc_trim", cheader = "malloc.h")]
        public extern static int malloc_trim (size_t pad);

        private const int MAX_WORKERS = 4;
        private static int active_workers = 0;
        private static ThreadPool<ThumbnailTask>? worker_pool = null;
        private static string? cache_dir = null;
        private static Queue<ThumbnailTask>? pending_queue = null;
        private static HashTable<string, ThumbnailTask>? in_flight_tasks = null;
        private static LruTextureCache? ram_cache = null;
        private static Mutex queue_mutex;

        private static GLib.Queue<ReadyThumbnail>? ready_queue = null;
        private static Mutex ready_mutex;
        private static uint flush_source_id = 0;

        public static string get_cache_dir() {
            if (cache_dir == null) {
                cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "vcmd", "thumbnails");
                var dir = File.new_for_path(cache_dir);
                if (!dir.query_exists()) {
                    try {
                        dir.make_directory_with_parents(null);
                    } catch (Error e) {
                        warning("Failed to create thumbnail cache dir: %s", e.message);
                    }
                }

                // Ensure .tmp directory exists
                var tmp_dir = File.new_for_path(Path.build_filename(cache_dir, ".tmp"));
                if (!tmp_dir.query_exists()) {
                    try {
                        tmp_dir.make_directory_with_parents(null);
                    } catch (Error e) {}
                }
            }
            return cache_dir;
        }

        public static string get_cache_file_path(string key) {
            string c_dir = get_cache_dir();
            string bucket = key.substring(0, 2);
            return Path.build_filename(c_dir, bucket, @"$key.png");
        }

        public static string get_tmp_file_path(string key) {
            string c_dir = get_cache_dir();
            return Path.build_filename(c_dir, ".tmp", @".tmp.$key.png");
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
            string legacy_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "thumbnails");
            if (path == legacy_dir || path.has_prefix(legacy_dir + "/") || path.has_prefix(legacy_dir + "\\")) {
                return true;
            }
            return false;
        }

        private static void delete_dir_recursively(File dir) {
            try {
                var enumerator = dir.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                FileInfo? info = null;
                while ((info = enumerator.next_file(null)) != null) {
                    var child = dir.get_child(info.get_name());
                    if (info.get_file_type() == FileType.DIRECTORY) {
                        delete_dir_recursively(child);
                    } else {
                        try { child.delete(null); } catch (Error e) {}
                    }
                }
                dir.delete(null);
            } catch (Error e) {}
        }

        public static void init() {
            get_cache_dir();
            pending_queue = new Queue<ThumbnailTask>();
            in_flight_tasks = new HashTable<string, ThumbnailTask>(str_hash, str_equal);
            ram_cache = new LruTextureCache(300);
            ready_queue = new GLib.Queue<ReadyThumbnail>();

            // 1. Clean up only lingering temporary files from .tmp directory
            try {
                var tmp_dir = File.new_for_path(Path.build_filename(cache_dir, ".tmp"));
                if (tmp_dir.query_exists()) {
                    var enumerator = tmp_dir.enumerate_children("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                    FileInfo? info = null;
                    while ((info = enumerator.next_file(null)) != null) {
                        var tmp_file = tmp_dir.get_child(info.get_name());
                        try {
                            tmp_file.delete(null);
                        } catch (Error e) {}
                    }
                }
            } catch (Error e) {
                // Ignore enumeration errors
            }

            // 2. Remove old legacy cache directory ~/.config/vcmd/thumbnails if present
            try {
                string legacy_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "thumbnails");
                var leg_f = File.new_for_path(legacy_dir);
                if (leg_f.query_exists()) {
                    delete_dir_recursively(leg_f);
                }
            } catch (Error e) {}

            // Initialize background worker pool with 4 threads
            try {
                worker_pool = new ThreadPool<ThumbnailTask>.with_owned_data(process_task, MAX_WORKERS, false);
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

        public static string compute_cache_key(string path, int64 mtime, int64 size, int dimension = 390) {
            string raw = @"$path:$mtime:$size:sq$dimension";
            return Checksum.compute_for_string(ChecksumType.SHA256, raw);
        }

        public static void request_thumbnail(FileItem item, int max_dimension = 390) {
            if (item.is_dir || item.is_parent_dir || item.is_thumbnail_requested) {
                return;
            }

            string? path = item.file.get_path();
            if (path == null || !is_supported_image(item.name) || item.name.has_prefix(".tmp.")) {
                return;
            }

            int64 mtime_val = (item.mtime != null) ? item.mtime.to_unix() : 0;
            string key = compute_cache_key(path, mtime_val, item.size);

            // 1. Check in-memory RAM cache first (instant hit, 0 I/O)
            if (ram_cache != null) {
                var cached_tex = ram_cache.get(key);
                if (cached_tex != null) {
                    item.is_thumbnail_requested = true;
                    item.thumbnail_paintable = cached_tex;
                    return;
                }
            }

            item.is_thumbnail_requested = true;

            // Exclude thumbnail cache directory from recursive thumbnail generation
            if (is_in_thumbnail_cache(path)) {
                Idle.add(() => {
                    try {
                        item.thumbnail_paintable = Gdk.Texture.from_file(item.file);
                    } catch (Error e) {}
                    return Source.REMOVE;
                });
                return;
            }

            string cache_file = get_cache_file_path(key);
            string tmp_file = get_tmp_file_path(key);

            // 2. Check in-flight tasks and prioritize LIFO
            queue_mutex.lock();
            if (in_flight_tasks != null && in_flight_tasks.contains(key)) {
                var existing_task = in_flight_tasks.lookup(key);
                if (existing_task != null && !existing_task.is_cancelled && pending_queue != null) {
                    // Re-prioritize to the head of the queue (LIFO boost)
                    pending_queue.remove(existing_task);
                    pending_queue.push_head(existing_task);
                }
                queue_mutex.unlock();
                return;
            }

            var task = new ThumbnailTask(item, path, cache_file, tmp_file, key);
            if (in_flight_tasks != null) {
                in_flight_tasks.insert(key, task);
            }
            if (pending_queue != null) {
                pending_queue.push_head(task); // LIFO: newest request at the head!
            }

            dispatch_workers_locked();
            queue_mutex.unlock();
        }

        public static void cancel_request(FileItem item) {
            if (!item.is_thumbnail_requested || item.is_dir || item.is_parent_dir) return;

            string? path = item.file.get_path();
            if (path == null) return;

            int64 mtime_val = (item.mtime != null) ? item.mtime.to_unix() : 0;
            string key = compute_cache_key(path, mtime_val, item.size);

            queue_mutex.lock();
            if (in_flight_tasks != null) {
                var task = in_flight_tasks.lookup(key);
                if (task != null) {
                    task.is_cancelled = true;
                    if (pending_queue != null) {
                        pending_queue.remove(task);
                    }
                    in_flight_tasks.remove(key);
                    item.is_thumbnail_requested = false;
                }
            }
            queue_mutex.unlock();
        }

        private static void dispatch_workers_locked() {
            if (worker_pool == null || pending_queue == null) return;

            while (active_workers < MAX_WORKERS && !pending_queue.is_empty()) {
                var candidate = pending_queue.pop_head();
                if (candidate == null) break;

                if (candidate.is_cancelled || candidate.get_item() == null) {
                    if (in_flight_tasks != null) {
                        in_flight_tasks.remove(candidate.key);
                    }
                    continue;
                }

                active_workers++;
                try {
                    worker_pool.add((owned) candidate);
                } catch (Error e) {
                    active_workers--;
                    if (in_flight_tasks != null) {
                        in_flight_tasks.remove(candidate.key);
                    }
                }
            }
        }

        private static void finish_task(string key) {
            queue_mutex.lock();
            if (in_flight_tasks != null) {
                in_flight_tasks.remove(key);
            }
            active_workers--;

            dispatch_workers_locked();

            bool is_empty = (active_workers == 0 && (pending_queue == null || pending_queue.is_empty()));
            queue_mutex.unlock();

            if (is_empty) {
                malloc_trim(0);
            }
        }

        private static void process_task(owned ThumbnailTask task) {
            string key = task.key;

            if (task.is_cancelled || task.get_item() == null) {
                finish_task(key);
                return;
            }

            Gdk.Texture? tex = null;
            var c_f = File.new_for_path(task.cache_path);

            // 1. Check if thumbnail already exists in disk cache
            if (c_f.query_exists()) {
                try {
                    tex = Gdk.Texture.from_file(c_f);
                } catch (Error e) {
                    // Corrupted cache file, will regenerate below
                    try {
                        c_f.delete(null);
                    } catch (Error del_err) {}
                    tex = null;
                }
            }

            // Early abort if cancelled
            if (tex == null && (task.is_cancelled || task.get_item() == null)) {
                finish_task(key);
                return;
            }

            // 2. Generate thumbnail if not on disk
            if (tex == null) {
                try {
                    const int TARGET_DIM = 390;
                    int orig_w = 0, orig_h = 0;
                    Gdk.Pixbuf.get_file_info(task.filepath, out orig_w, out orig_h);

                    int scale_w = -1;
                    int scale_h = -1;
                    if (orig_w > 0 && orig_h > 0) {
                        if (orig_w <= orig_h) {
                            scale_w = TARGET_DIM;
                            scale_h = -1;
                        } else {
                            scale_w = -1;
                            scale_h = TARGET_DIM;
                        }
                    } else {
                        scale_w = TARGET_DIM;
                        scale_h = -1;
                    }

                    var pixbuf = new Gdk.Pixbuf.from_file_at_scale(task.filepath, scale_w, scale_h, true);
                    if (pixbuf != null) {
                        var oriented = pixbuf.apply_embedded_orientation();
                        var pb = (oriented != null) ? oriented : pixbuf;

                        int cur_w = pb.get_width();
                        int cur_h = pb.get_height();

                        // Ensure minimum dimension is at least TARGET_DIM
                        if (cur_w < TARGET_DIM || cur_h < TARGET_DIM) {
                            int new_w, new_h;
                            if (cur_w <= cur_h) {
                                new_w = TARGET_DIM;
                                new_h = (int) ((int64) cur_h * TARGET_DIM / int.max(1, cur_w));
                            } else {
                                new_h = TARGET_DIM;
                                new_w = (int) ((int64) cur_w * TARGET_DIM / int.max(1, cur_h));
                            }
                            var rescaled = pb.scale_simple(new_w, new_h, Gdk.InterpType.BILINEAR);
                            if (rescaled != null) {
                                pb = rescaled;
                                cur_w = new_w;
                                cur_h = new_h;
                            }
                        }

                        // Center-crop to a square (TARGET_DIM x TARGET_DIM)
                        int crop_x = int.max(0, (cur_w - TARGET_DIM) / 2);
                        int crop_y = int.max(0, (cur_h - TARGET_DIM) / 2);
                        int crop_w = int.min(TARGET_DIM, cur_w);
                        int crop_h = int.min(TARGET_DIM, cur_h);

                        var final_pb = new Gdk.Pixbuf.subpixbuf(pb, crop_x, crop_y, crop_w, crop_h);

                        if (!task.is_cancelled && task.get_item() != null) {
                            final_pb.save(task.tmp_path, "png");

                            string bucket_dir_path = Path.get_dirname(task.cache_path);
                            var bucket_dir = File.new_for_path(bucket_dir_path);
                            if (!bucket_dir.query_exists()) {
                                try {
                                    bucket_dir.make_directory_with_parents(null);
                                } catch (Error err) {}
                            }

                            GLib.FileUtils.rename(task.tmp_path, task.cache_path);

                            // Load texture on worker thread
                            tex = Gdk.Texture.from_file(c_f);
                        }
                    }
                } catch (Error e) {
                    var tmp_f = File.new_for_path(task.tmp_path);
                    try {
                        tmp_f.delete(null);
                    } catch (Error err) {}
                }
            }

            // Early abort if cancelled before delivery
            if (task.is_cancelled || task.get_item() == null) {
                finish_task(key);
                return;
            }

            // 3. Save to in-memory cache and enqueue for batched delivery
            if (tex != null) {
                if (ram_cache != null) {
                    ram_cache.put(key, tex);
                }

                var target_item = task.get_item();
                if (target_item != null) {
                    enqueue_ready_thumbnail(target_item, tex);
                }
            }

            finish_task(key);
        }

        private static void enqueue_ready_thumbnail(FileItem item, Gdk.Texture tex) {
            ready_mutex.lock();
            if (ready_queue == null) {
                ready_queue = new GLib.Queue<ReadyThumbnail>();
            }
            ready_queue.push_tail(new ReadyThumbnail(item, tex));
            if (flush_source_id == 0) {
                flush_source_id = Idle.add_full(Priority.DEFAULT_IDLE, flush_ready_batch);
            }
            ready_mutex.unlock();
        }

        private static bool flush_ready_batch() {
            const int BATCH_SIZE = 25;
            var batch = new GenericArray<ReadyThumbnail>();

            ready_mutex.lock();
            if (ready_queue == null || ready_queue.is_empty()) {
                flush_source_id = 0;
                ready_mutex.unlock();
                return Source.REMOVE;
            }

            int count = 0;
            while (!ready_queue.is_empty() && count < BATCH_SIZE) {
                var item = ready_queue.pop_head();
                if (item != null) {
                    batch.add(item);
                    count++;
                }
            }

            bool has_more = !ready_queue.is_empty();
            if (!has_more) {
                flush_source_id = 0;
            }
            ready_mutex.unlock();

            for (int i = 0; i < batch.length; i++) {
                var ready = batch[i];
                var target_item = ready.get_item();
                if (target_item != null && target_item.thumbnail_paintable == null) {
                    target_item.thumbnail_paintable = ready.texture;
                }
            }

            return has_more ? Source.CONTINUE : Source.REMOVE;
        }
    }
}
