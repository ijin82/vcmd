namespace VCommander {

    public enum LogLevel {
        INFO,
        WARN,
        ERROR,
        DEBUG;

        public string to_string() {
            switch (this) {
                case INFO: return "INFO";
                case WARN: return "WARN";
                case ERROR: return "ERROR";
                case DEBUG: return "DEBUG";
                default: return "INFO";
            }
        }
    }

    public class AppLogger : Object {
        private static GLib.Mutex log_mutex = GLib.Mutex();
        private static string? cached_log_path = null;

        public static string get_log_file_path() {
            if (cached_log_path != null) return cached_log_path;

            string config_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd");
            if (!FileUtils.test(config_dir, FileTest.IS_DIR)) {
                DirUtils.create_with_parents(config_dir, 0755);
            }
            cached_log_path = Path.build_filename(config_dir, "vcmd.log");
            return cached_log_path;
        }

        public static void init() {
            ensure_reverse_order();
            purge_entries_older_than_days(3);
            info("System", "Application started. Retaining log entries from the last 3 days.");
        }

        private static void ensure_reverse_order() {
            log_mutex.lock();
            string path = get_log_file_path();
            if (!FileUtils.test(path, FileTest.EXISTS)) {
                log_mutex.unlock();
                return;
            }
            try {
                string contents;
                FileUtils.get_contents(path, out contents);
                string[] lines = contents.split("\n");

                string? first_ts = null;
                string? last_ts = null;
                foreach (var line in lines) {
                    if (line.has_prefix("[") && line.length >= 21) {
                        if (first_ts == null) first_ts = line.substring(0, 21);
                        last_ts = line.substring(0, 21);
                    }
                }

                if (first_ts != null && last_ts != null && first_ts < last_ts) {
                    var reversed = new StringBuilder();
                    for (int i = lines.length - 1; i >= 0; i--) {
                        var line = lines[i].strip();
                        if (line.length > 0) {
                            reversed.append(line);
                            reversed.append_c('\n');
                        }
                    }
                    FileUtils.set_contents(path, reversed.str);
                }
            } catch (Error e) {
                stderr.printf("AppLogger: Failed to ensure reverse order: %s\n", e.message);
            } finally {
                log_mutex.unlock();
            }
        }

        public static void purge_entries_older_than_days(int days) {
            log_mutex.lock();
            string path = get_log_file_path();
            if (!FileUtils.test(path, FileTest.EXISTS)) {
                log_mutex.unlock();
                return;
            }

            try {
                var cutoff = new DateTime.now_local().add_days(-days);
                string cutoff_ts = cutoff.format("[%Y-%m-%d %H:%M:%S]");

                string contents;
                FileUtils.get_contents(path, out contents);
                string[] lines = contents.split("\n");

                var retained = new StringBuilder();
                bool last_kept = false;

                foreach (var line in lines) {
                    if (line.length == 0) continue;

                    if (line.has_prefix("[") && line.length >= 21) {
                        string ts = line.substring(0, 21);
                        if (ts >= cutoff_ts) {
                            retained.append(line);
                            retained.append_c('\n');
                            last_kept = true;
                        } else {
                            last_kept = false;
                        }
                    } else if (last_kept) {
                        retained.append(line);
                        retained.append_c('\n');
                    }
                }

                FileUtils.set_contents(path, retained.str);
            } catch (Error e) {
                stderr.printf("AppLogger: Failed to purge old log entries: %s\n", e.message);
            } finally {
                log_mutex.unlock();
            }
        }

        /**
         * Unified, extensible logging method.
         * Guarantees consistent format for all application events:
         * [YYYY-MM-DD HH:MM:SS] [LEVEL] [Category] Message
         *
         * @param level Severity level (INFO, WARN, ERROR, DEBUG)
         * @param category Functional category (e.g. "System", "FileOperation", "DriveQueue", "Storage")
         * @param message Description of the event
         * @param details Optional key-value or supplementary details to append
         */
        public static void write_entry(LogLevel level, string category, string message, string? details = null) {
            log_mutex.lock();
            string path = get_log_file_path();
            var now = new DateTime.now_local();
            string timestamp = now.format("[%Y-%m-%d %H:%M:%S]");
            string level_str = @"[$(level.to_string())]";
            string cat_str = (category != null && category.length > 0) ? @"[$category]" : "[General]";

            string formatted_line;
            if (details != null && details.length > 0) {
                formatted_line = @"$timestamp $level_str $cat_str $message ($details)\n";
            } else {
                formatted_line = @"$timestamp $level_str $cat_str $message\n";
            }

            stderr.printf("%s", formatted_line);

            try {
                string existing = "";
                if (FileUtils.test(path, FileTest.EXISTS)) {
                    FileUtils.get_contents(path, out existing);
                }
                FileUtils.set_contents(path, formatted_line + existing);
            } catch (Error e) {
                stderr.printf("AppLogger: Failed to write log entry: %s\n", e.message);
            }
            log_mutex.unlock();
        }

        public static void info(string category, string message, string? details = null) {
            write_entry(LogLevel.INFO, category, message, details);
        }

        public static void warn(string category, string message, string? details = null) {
            write_entry(LogLevel.WARN, category, message, details);
        }

        public static void error(string category, string message, string? details = null) {
            write_entry(LogLevel.ERROR, category, message, details);
        }

        public static void debug(string category, string message, string? details = null) {
            write_entry(LogLevel.DEBUG, category, message, details);
        }
    }
}
