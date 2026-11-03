namespace VCommander {

    public class DeviceDetector : Object {

        public static string get_device_id(File file) {
            string? uri = file.get_uri();
            if (uri != null && !uri.has_prefix("file://")) {
                string scheme = file.get_uri_scheme();
                if (scheme != null && scheme.length > 0) {
                    try {
                        var mount = file.find_enclosing_mount(null);
                        if (mount != null) {
                            return mount.get_root().get_uri();
                        }
                    } catch (Error e) {}

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
            string cur_path = path;
            while (!FileUtils.test(cur_path, FileTest.EXISTS)) {
                string parent = Path.get_dirname(cur_path);
                if (parent == cur_path || parent.length == 0) break;
                cur_path = parent;
            }

            Posix.Stat st;
            if (Posix.stat(cur_path, out st) != 0) {
                return "unknown";
            }

            uint64 dev = (uint64) st.st_dev;
            uint maj = (uint) (((dev >> 8) & 0xfff) | ((dev >> 32) & ~0xfff));
            uint min = (uint) ((dev & 0xff) | ((dev >> 12) & ~0xff));

            string sys_block = @"/sys/dev/block/$maj:$min";
            string? real_sys_path = null;
            try {
                real_sys_path = FileUtils.read_link(sys_block);
            } catch (Error e) {
                real_sys_path = null;
            }

            if (real_sys_path == null) {
                return @"dev_$dev";
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
                    if (p != null && FileUtils.test(p, FileTest.EXISTS)) {
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
