namespace VCommander {

    public class QueuedTask {
        public string id;
        public GenericArray<string> required_disks;
        public OperationProgressDialog dlg;
        public Cancellable? cancellable;
        public SourceFunc? resume_callback;
        public bool is_cancelled = false;

        public QueuedTask(string id, GenericArray<string> required_disks, OperationProgressDialog dlg, Cancellable? cancellable) {
            this.id = id;
            this.required_disks = required_disks;
            this.dlg = dlg;
            this.cancellable = cancellable;
        }
    }

    public class DriveQueueManager : Object {
        private static DriveQueueManager? instance = null;

        public signal void queue_changed();

        private HashTable<string, int> active_disks;
        private GenericArray<QueuedTask> queue;
        private GenericArray<QueuedTask> active_tasks;

        public static DriveQueueManager get_instance() {
            if (instance == null) {
                instance = new DriveQueueManager();
            }
            return instance;
        }

        public DriveQueueManager() {
            active_disks = new HashTable<string, int>(str_hash, str_equal);
            queue = new GenericArray<QueuedTask>();
            active_tasks = new GenericArray<QueuedTask>();
        }

        public int queued_count {
            get { return queue.length; }
        }

        public int active_count {
            get { return active_tasks.length; }
        }

        public static GenericArray<string> get_required_disks(File? source, File? dest) {
            var list = new GenericArray<string>();
            if (source != null) {
                string src_id = DeviceDetector.get_device_id(source);
                if (src_id.length > 0 && src_id != "unknown") {
                    list.add(src_id);
                }
            }
            if (dest != null) {
                string dst_id = DeviceDetector.get_device_id(dest);
                if (dst_id.length > 0 && dst_id != "unknown") {
                    bool already = false;
                    for (int i = 0; i < list.length; i++) {
                        if (list[i] == dst_id) { already = true; break; }
                    }
                    if (!already) {
                        list.add(dst_id);
                    }
                }
            }
            return list;
        }

        public static GenericArray<string> get_required_disks_multi(GenericArray<FileItem> items, File dest_dir) {
            var list = new GenericArray<string>();
            string dst_id = DeviceDetector.get_device_id(dest_dir);
            if (dst_id.length > 0 && dst_id != "unknown") {
                list.add(dst_id);
            }
            if (items.length > 0) {
                string src_id = DeviceDetector.get_device_id(items[0].file);
                if (src_id.length > 0 && src_id != "unknown") {
                    bool already = false;
                    for (int i = 0; i < list.length; i++) {
                        if (list[i] == src_id) { already = true; break; }
                    }
                    if (!already) {
                        list.add(src_id);
                    }
                }
            }
            return list;
        }

        public string? get_first_busy_disk(GenericArray<string> disks) {
            for (int i = 0; i < disks.length; i++) {
                string d = disks[i];
                int count = active_disks.contains(d) ? active_disks.get(d) : 0;
                if (count > 0) {
                    return d;
                }
            }
            return null;
        }

        private void mark_disks_active(GenericArray<string> disks) {
            for (int i = 0; i < disks.length; i++) {
                string d = disks[i];
                int count = active_disks.contains(d) ? active_disks.get(d) : 0;
                active_disks.insert(d, count + 1);
            }
        }

        private void unmark_disks_active(GenericArray<string> disks) {
            for (int i = 0; i < disks.length; i++) {
                string d = disks[i];
                int count = active_disks.contains(d) ? active_disks.get(d) : 0;
                if (count > 1) {
                    active_disks.insert(d, count - 1);
                } else {
                    active_disks.remove(d);
                }
            }
        }

        public async void acquire_disks_async(GenericArray<string> disks, OperationProgressDialog dlg, Cancellable? cancellable) throws Error {
            if (cancellable != null && cancellable.is_cancelled()) {
                throw new IOError.CANCELLED("Operation cancelled");
            }

            string? busy = get_first_busy_disk(disks);
            if (busy == null) {
                // Free to run immediately!
                mark_disks_active(disks);
                var task = new QueuedTask(dlg.op_title, disks, dlg, cancellable);
                active_tasks.add(task);
                AppLogger.info("DriveQueue", @"Acquired disk lock for '$(dlg.op_title)' on: $(format_disks_str(disks))");
                queue_changed();
                return;
            }

            // Busy disk detected: place in queue
            string friendly_name = DeviceDetector.format_device_name(busy);
            dlg.set_queued(friendly_name);
            dlg.minimize();

            var task = new QueuedTask(dlg.op_title, disks, dlg, cancellable);
            queue.add(task);
            queue_changed();
            AppLogger.info("DriveQueue", @"Disk '$busy' ($friendly_name) is busy. Operation '$(dlg.op_title)' placed in queue (#$(queue.length))");

            ulong cancel_id = 0;
            if (cancellable != null) {
                cancel_id = cancellable.connect(() => {
                    task.is_cancelled = true;
                    for (int i = 0; i < queue.length; i++) {
                        if (queue[i] == task) {
                            queue.remove_index(i);
                            break;
                        }
                    }
                    queue_changed();
                    AppLogger.info("DriveQueue", @"Operation '$(task.id)' cancelled while in queue");
                    if (task.resume_callback != null) {
                        var cb = task.resume_callback;
                        task.resume_callback = null;
                        cb();
                    }
                });
            }

            task.resume_callback = acquire_disks_async.callback;
            yield;

            if (cancellable != null && cancel_id != 0) {
                cancellable.disconnect(cancel_id);
            }

            if (task.is_cancelled || (cancellable != null && cancellable.is_cancelled())) {
                throw new IOError.CANCELLED("Operation cancelled while queued");
            }

            mark_disks_active(disks);
            active_tasks.add(task);
            dlg.set_dequeued();
            queue_changed();
            AppLogger.info("DriveQueue", @"Operation '$(dlg.op_title)' dispatched from queue, acquired lock on: $(format_disks_str(disks))");
        }

        public void release_disks(GenericArray<string> disks, OperationProgressDialog dlg) {
            unmark_disks_active(disks);

            for (int i = 0; i < active_tasks.length; i++) {
                if (active_tasks[i].dlg == dlg) {
                    active_tasks.remove_index(i);
                    break;
                }
            }

            AppLogger.info("DriveQueue", @"Released disk lock for '$(dlg.op_title)' on: $(format_disks_str(disks))");
            queue_changed();
            check_and_dispatch_next();
        }

        public int get_queue_position(OperationProgressDialog dlg) {
            for (int i = 0; i < queue.length; i++) {
                if (queue[i].dlg == dlg) {
                    return i + 1;
                }
            }
            return -1;
        }

        public bool move_queue_task_up(OperationProgressDialog dlg) {
            for (int i = 1; i < queue.length; i++) {
                if (queue[i].dlg == dlg) {
                    var tmp = queue[i];
                    queue[i] = queue[i - 1];
                    queue[i - 1] = tmp;
                    queue_changed();
                    return true;
                }
            }
            return false;
        }

        public bool move_queue_task_down(OperationProgressDialog dlg) {
            for (int i = 0; i < queue.length - 1; i++) {
                if (queue[i].dlg == dlg) {
                    var tmp = queue[i];
                    queue[i] = queue[i + 1];
                    queue[i + 1] = tmp;
                    queue_changed();
                    return true;
                }
            }
            return false;
        }

        public GenericArray<OperationProgressDialog> get_all_queued_dialogs() {
            var list = new GenericArray<OperationProgressDialog>();
            for (int i = 0; i < queue.length; i++) {
                if (!queue[i].is_cancelled) {
                    list.add(queue[i].dlg);
                }
            }
            return list;
        }

        private string format_disks_str(GenericArray<string> disks) {
            var sb = new StringBuilder();
            for (int i = 0; i < disks.length; i++) {
                if (i > 0) sb.append(", ");
                sb.append(disks[i]);
            }
            return sb.str;
        }

        private void check_and_dispatch_next() {
            for (int i = 0; i < queue.length; i++) {
                var candidate = queue[i];
                if (candidate.is_cancelled) continue;

                string? busy = get_first_busy_disk(candidate.required_disks);
                if (busy == null) {
                    // All required disks are free for this candidate
                    queue.remove_index(i);
                    queue_changed();
                    if (candidate.resume_callback != null) {
                        var cb = candidate.resume_callback;
                        candidate.resume_callback = null;
                        cb();
                    }
                    // Continue scanning to wake up other tasks on independent disks
                    i--;
                }
            }
        }
    }
}
