namespace VCommander {

    public class FileSearchQuery : Object {
        public File root { get; set; }
        public string name_pattern { get; set; default = "*"; }
        public bool name_specified { get; set; default = false; }
        public string content_needle { get; set; default = ""; }
        public bool content_specified { get; set; default = false; }
        public bool case_sensitive { get; set; default = false; }
        public bool include_hidden { get; set; default = false; }
    }

    public class FileSearchEngine : Object {
        public const int MAX_RESULTS = 5000;
        public const int64 MAX_CONTENT_BYTES = 32 * 1024 * 1024;

        private const string ENUM_ATTRS = "standard::name,standard::display-name,standard::type,standard::size,standard::is-hidden,standard::is-symlink,standard::symlink-target,standard::icon,time::modified,owner::user,owner::group,unix::uid,unix::user-name,unix::gid,unix::group-name,unix::mode,unix::inode,unix::device";

        public signal void progress(string current_path, int found, int scanned);

        private FileSearchQuery query;
        private PatternSpec name_spec;
        private GenericSet<string> visited;
        private int skipped_dirs;
        private bool truncated;

        public FileSearchEngine(FileSearchQuery query) {
            this.query = query;
            this.name_spec = new PatternSpec(query.name_pattern);
            this.visited = new GenericSet<string>(str_hash, str_equal);
        }

        public async GenericArray<FileItem> run(Cancellable cancellable) throws Error {
            var results = new GenericArray<FileItem>();
            var queue = new GenericArray<File>();
            queue.add(query.root);

            int scanned = 0;
            int since_progress = 0;

            while (queue.length > 0) {
                if (cancellable.is_cancelled()) {
                    break;
                }
                if (results.length >= MAX_RESULTS) {
                    truncated = true;
                    break;
                }

                File dir = queue.get(0);
                queue.remove_index(0);
                string dir_key = visit_key(dir, null);
                if (visited.contains(dir_key)) {
                    continue;
                }
                visited.add(dir_key);

                FileEnumerator enumerator;
                try {
                    enumerator = yield dir.enumerate_children_async(
                        ENUM_ATTRS,
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                        Priority.DEFAULT_IDLE,
                        cancellable
                    );
                } catch (IOError.CANCELLED e) {
                    break;
                } catch (Error e) {
                    skipped_dirs++;
                    continue;
                }

                while (true) {
                    if (cancellable.is_cancelled() || results.length >= MAX_RESULTS) {
                        truncated = results.length >= MAX_RESULTS;
                        break;
                    }

                    List<FileInfo> infos;
                    try {
                        infos = yield enumerator.next_files_async(40, Priority.DEFAULT_IDLE, cancellable);
                    } catch (IOError.CANCELLED e) {
                        break;
                    } catch (Error e) {
                        skipped_dirs++;
                        break;
                    }
                    if (infos == null || infos.length() == 0) {
                        break;
                    }

                    foreach (var info in infos) {
                        if (cancellable.is_cancelled() || results.length >= MAX_RESULTS) {
                            truncated = results.length >= MAX_RESULTS;
                            break;
                        }

                        string name = info.get_name();
                        bool hidden = info.get_is_hidden() || name.has_prefix(".");
                        if (hidden && !query.include_hidden) {
                            continue;
                        }

                        scanned++;
                        since_progress++;
                        var child = dir.get_child(name);
                        bool is_dir = info.get_file_type() == FileType.DIRECTORY;
                        bool is_link = info.get_is_symlink();

                        if (matches_name(name)) {
                            bool accept = false;
                            if (is_dir) {
                                accept = query.name_specified || !query.content_specified;
                            } else if (!query.content_specified) {
                                accept = true;
                            } else if (info.get_size() <= MAX_CONTENT_BYTES) {
                                try {
                                    accept = yield file_contains(child, query.content_needle, query.case_sensitive, cancellable);
                                } catch (IOError.CANCELLED e) {
                                    break;
                                } catch (Error e) {
                                    accept = false;
                                }
                            }
                            if (accept) {
                                var item = new FileItem(child, info);
                                string? rel = query.root.get_relative_path(child);
                                if (rel != null && rel.length > 0) {
                                    item.display_name = rel;
                                }
                                results.add(item);
                            }
                        }

                        if (is_dir && !is_link) {
                            queue.add(child);
                        }

                    }

                    if (since_progress >= 30) {
                        since_progress = 0;
                        progress(dir.get_parse_name(), results.length, scanned);
                        Idle.add(run.callback);
                        yield;
                    }
                }

                try {
                    yield enumerator.close_async(Priority.DEFAULT_IDLE, cancellable);
                } catch (Error e) {
                }
            }

            progress(query.root.get_parse_name(), results.length, scanned);
            return results;
        }

        public string summary(int found, bool cancelled) {
            string text;
            if (cancelled && found == 0) {
                text = "Search cancelled";
            } else if (cancelled) {
                text = @"Search stopped — $found matches";
            } else if (found == 0) {
                text = "No matches";
            } else {
                text = @"$found matches";
            }
            if (truncated) {
                text += @" (limit $(MAX_RESULTS))";
            }
            if (skipped_dirs > 0) {
                text += @" | $skipped_dirs unreadable";
            }
            return text;
        }

        public bool hit_limit {
            get { return truncated; }
        }

        private bool matches_name(string name) {
            string candidate = query.case_sensitive ? name : name.down();
            return name_spec.match_string(candidate);
        }

        private static string visit_key(File file, FileInfo? info) {
            if (info != null && info.has_attribute("unix::inode")) {
                uint64 ino = info.get_attribute_uint64("unix::inode");
                uint32 dev = info.has_attribute("unix::device") ? info.get_attribute_uint32("unix::device") : 0;
                if (ino != 0) {
                    return @"$dev:$ino";
                }
            }
            return file.get_uri();
        }

        private async bool file_contains(File file, string needle, bool case_sensitive, Cancellable cancellable) throws Error {
            if (needle.length == 0) {
                return true;
            }
            var stream = yield file.read_async(Priority.DEFAULT_IDLE, cancellable);
            var input = new DataInputStream(stream);
            input.close_base_stream = true;

            string carry = "";
            int keep = int.max(needle.length - 1, 0);
            bool first = true;
            var buf = new uint8[65536];

            while (true) {
                ssize_t n = yield input.read_async(buf, Priority.DEFAULT_IDLE, cancellable);
                if (n <= 0) {
                    break;
                }
                int len = (int) n;
                if (first) {
                    first = false;
                    int check = int.min(len, 4096);
                    for (int i = 0; i < check; i++) {
                        if (buf[i] == 0) {
                            return false;
                        }
                    }
                }
                for (int i = 0; i < len; i++) {
                    if (buf[i] == 0) {
                        return false;
                    }
                }

                var copy = new uint8[len + 1];
                Memory.copy(copy, buf, len);
                copy[len] = 0;
                string chunk = (string) copy;
                if (!case_sensitive) {
                    chunk = chunk.down();
                }
                string window = carry + chunk;
                if (window.contains(needle)) {
                    return true;
                }
                if (keep > 0 && window.length > keep) {
                    carry = window.substring(window.length - keep);
                } else {
                    carry = window;
                }
            }
            return false;
        }

        public static string normalize_name_pattern(string raw, bool case_sensitive, out bool specified) {
            string pattern = raw.strip();
            specified = pattern.length > 0;
            if (!specified) {
                return "*";
            }
            if (!pattern.contains("*") && !pattern.contains("?") && !pattern.contains("[")) {
                pattern = "*" + pattern + "*";
            }
            if (!case_sensitive) {
                pattern = pattern.down();
            }
            return pattern;
        }
    }
}
