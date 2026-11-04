namespace VCommander {

    public class DeviceDetector : Object {

        public static string get_device_id(File file) {
            string? uri = file.get_uri();
            if (uri != null && !uri.has_prefix("file://")) {
                string scheme = file.get_uri_scheme();
                if (scheme != null && scheme.length > 0) {
                    string[] parts = uri.split("/");
                    if (parts.length >= 3 && parts[2].length > 0) {
                        return @"$scheme://$(parts[2])";
                    }
                    return scheme;
                }
            }

            string? path = file.get_path();
            if (path == null) {
                path = file.get_parse_name();
            }
            if (path == null || path.length == 0) {
                return "unknown";
            }

            return get_path_disk_id(path);
        }

        public static string get_path_disk_id(string path) {
            string? majmin = find_mountinfo_majmin(path);
            if (majmin != null) {
                string disk = resolve_sysfs_disk_id(majmin);
                if (disk.length > 0 && disk != "unknown") {
                    return disk;
                }
            }

            // Fallback: in-memory stat only if mountinfo is not available
            return fallback_stat_disk_id(path);
        }

        private static string unescape_mountinfo_path(string s) {
            if (!s.contains("\\")) return s;
            var sb = new StringBuilder();
            int len = s.length;
            for (int i = 0; i < len; i++) {
                if (s[i] == '\\' && i + 3 < len &&
                    s[i+1] >= '0' && s[i+1] <= '7' &&
                    s[i+2] >= '0' && s[i+2] <= '7' &&
                    s[i+3] >= '0' && s[i+3] <= '7') {
                    int code = (s[i+1] - '0') * 64 + (s[i+2] - '0') * 8 + (s[i+3] - '0');
                    sb.append_c((char) code);
                    i += 3;
                } else {
                    sb.append_c(s[i]);
                }
            }
            return sb.str;
        }

        private static string? find_mountinfo_majmin(string target_path) {
            try {
                var file = File.new_for_path("/proc/self/mountinfo");
                if (!file.query_exists()) return null;

                var dis = new DataInputStream(file.read());
                string? line = null;
                string? best_mount = null;
                string? best_majmin = null;

                while ((line = dis.read_line(null)) != null) {
                    string[] parts = line.strip().split(" ");
                    if (parts.length >= 5) {
                        string majmin = parts[2];
                        string mount_point = unescape_mountinfo_path(parts[4]);

                        bool matches = false;
                        if (target_path == mount_point) {
                            matches = true;
                        } else if (mount_point == "/") {
                            matches = true;
                        } else if (target_path.has_prefix(mount_point + "/")) {
                            matches = true;
                        }

                        if (matches) {
                            if (best_mount == null || mount_point.length > best_mount.length) {
                                best_mount = mount_point;
                                best_majmin = majmin;
                            }
                        }
                    }
                }
                return best_majmin;
            } catch (Error e) {
                return null;
            }
        }

        private static string resolve_sysfs_disk_id(string majmin) {
            string sys_block = @"/sys/dev/block/$majmin";
            string? real_sys_path = null;
            try {
                real_sys_path = FileUtils.read_link(sys_block);
            } catch (Error e) {
                real_sys_path = null;
            }

            if (real_sys_path == null) {
                return @"dev_$majmin";
            }

            string full_sys_path = real_sys_path;
            if (!full_sys_path.has_prefix("/")) {
                full_sys_path = Path.build_filename("/sys/dev/block", real_sys_path);
            }
            try {
                var f = File.new_for_path(full_sys_path);
                full_sys_path = f.get_path();
            } catch (Error e) {}

            // Check if device-mapper (e.g. LUKS dm-crypt), resolve underlying slave disk
            string slaves_dir = Path.build_filename(full_sys_path, "slaves");
            if (FileUtils.test(slaves_dir, FileTest.IS_DIR)) {
                try {
                    var dir = Dir.open(slaves_dir);
                    string? slave_name = dir.read_name();
                    if (slave_name != null) {
                        string slave_sys = Path.build_filename("/sys/class/block", slave_name);
                        string? slave_real = null;
                        try {
                            slave_real = FileUtils.read_link(slave_sys);
                        } catch (Error e) {}
                        if (slave_real != null) {
                            if (!slave_real.has_prefix("/")) {
                                slave_real = Path.build_filename("/sys/class/block", slave_real);
                            }
                            try {
                                var sf = File.new_for_path(slave_real);
                                slave_real = sf.get_path();
                            } catch (Error e) {}
                            return extract_disk_name_from_sysfs(slave_real);
                        }
                        return slave_name;
                    }
                } catch (Error e) {}
            }

            return extract_disk_name_from_sysfs(full_sys_path);
        }

        private static string fallback_stat_disk_id(string path) {
            string cur_path = path;
            int depth = 0;
            while (!FileUtils.test(cur_path, FileTest.EXISTS) && depth < 20) {
                string parent = Path.get_dirname(cur_path);
                if (parent == cur_path || parent.length == 0) break;
                cur_path = parent;
                depth++;
            }

            Posix.Stat st;
            if (Posix.stat(cur_path, out st) != 0) {
                return "unknown";
            }

            uint64 dev = (uint64) st.st_dev;
            uint maj = (uint) (((dev >> 8) & 0xfff) | ((dev >> 32) & ~0xfff));
            uint min = (uint) ((dev & 0xff) | ((dev >> 12) & ~0xff));
            return resolve_sysfs_disk_id(@"$maj:$min");
        }

        private static string extract_disk_name_from_sysfs(string sys_path) {
            string part_file = Path.build_filename(sys_path, "partition");
            if (FileUtils.test(part_file, FileTest.EXISTS)) {
                return Path.get_basename(Path.get_dirname(sys_path));
            }
            return Path.get_basename(sys_path);
        }

        public static string format_device_name(string disk_id) {
            if (disk_id.has_prefix("sftp://") || disk_id.has_prefix("smb://")) {
                return disk_id;
            }

            try {
                var vm = VolumeMonitor.get();
                var mounts = vm.get_mounts();
                foreach (var m in mounts) {
                    var r = m.get_root();
                    string? p = r.get_path();
                    if (p != null) {
                        // get_path_disk_id uses /proc/self/mountinfo in RAM (zero disk I/O)
                        if (get_path_disk_id(p) == disk_id) {
                            return @"$(m.get_name()) ($disk_id)";
                        }
                    }
                }
            } catch (Error e) {}

            if (disk_id.has_prefix("nvme")) {
                return @"Local SSD ($disk_id)";
            }
            if (disk_id.has_prefix("sd")) {
                return @"Disk ($disk_id)";
            }
            return disk_id;
        }
    }
}
