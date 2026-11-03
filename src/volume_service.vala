namespace VCommander {

    public enum LocationCategory {
        DEVICE,
        NETWORK,
        PLACE,
        ACTION
    }

    public class LocationItem : Object {
        public string id { get; set; }
        public string name { get; set; }
        public string? subtitle { get; set; default = null; }
        public Icon? icon { get; set; default = null; }
        public File? file { get; set; default = null; }
        public LocationCategory category { get; set; default = LocationCategory.DEVICE; }
        public Mount? mount { get; set; default = null; }
        public Volume? volume { get; set; default = null; }
        public Drive? drive { get; set; default = null; }
        public bool is_mounted { get; set; default = true; }
        public bool can_eject { get; set; default = false; }
        public bool can_unmount { get; set; default = false; }
        public bool is_encrypted { get; set; default = false; }
        public string? encrypted_backing_device { get; set; default = null; }

        public LocationItem(string id, string name, LocationCategory category, File? file = null, Icon? icon = null, string? subtitle = null) {
            this.id = id;
            this.name = name;
            this.category = category;
            this.file = file;
            this.icon = icon;
            this.subtitle = subtitle;
        }
    }

    public class VolumeService : Object {
        private static VolumeService? instance = null;
        private VolumeMonitor monitor;

        public signal void changed();

        public static VolumeService get_instance() {
            if (instance == null) {
                instance = new VolumeService();
            }
            return instance;
        }

        private VolumeService() {
            monitor = VolumeMonitor.get();

            monitor.mount_added.connect((m) => { changed(); });
            monitor.mount_removed.connect((m) => { changed(); });
            monitor.mount_changed.connect((m) => { changed(); });

            monitor.volume_added.connect((v) => { changed(); });
            monitor.volume_removed.connect((v) => { changed(); });
            monitor.volume_changed.connect((v) => { changed(); });

            monitor.drive_connected.connect((d) => { changed(); });
            monitor.drive_disconnected.connect((d) => { changed(); });
            monitor.drive_changed.connect((d) => { changed(); });
        }

        public GenericArray<LocationItem> get_locations() {
            var items = new GenericArray<LocationItem>();

            // 1. Devices & Removable Drives: File System Root
            var root_file = File.new_for_path("/");
            var root_item = new LocationItem("root", "File System", LocationCategory.DEVICE, root_file, new ThemedIcon("drive-harddisk-symbolic"), "/");
            items.add(root_item);

            // Active Mounts
            var mounts = monitor.get_mounts();
            var seen_volume_ids = new GenericSet<string>(str_hash, str_equal);

            foreach (var m in mounts) {
                if (m.is_shadowed()) {
                    continue;
                }

                var root = m.get_root();
                if (root == null) {
                    continue;
                }

                string uri = root.get_uri();
                if (uri == "file:///") {
                    continue;
                }

                var vol = m.get_volume();
                if (vol != null) {
                    string? vol_id = vol.get_identifier("uuid");
                    if (vol_id == null) {
                        vol_id = vol.get_name();
                    }
                    seen_volume_ids.add(vol_id);
                }

                string? scheme = root.get_uri_scheme();
                bool is_remote = false;
                if (scheme != null && (scheme == "dav" || scheme == "davs" || scheme == "sftp" || scheme == "ssh" ||
                                       scheme == "smb" || scheme == "ftp" || scheme == "ftps" || scheme == "afp" ||
                                       scheme == "nfs" || scheme == "google-drive" || scheme == "network")) {
                    is_remote = true;
                } else if (RemoteMount.is_remote_path(uri)) {
                    is_remote = true;
                }

                LocationCategory cat = is_remote ? LocationCategory.NETWORK : LocationCategory.DEVICE;

                Icon? icon = m.get_symbolic_icon();
                if (icon == null) {
                    icon = m.get_icon();
                }
                if (icon == null) {
                    icon = new ThemedIcon(is_remote ? "folder-remote-symbolic" : "drive-harddisk-symbolic");
                }

                string name = m.get_name();
                string subtitle = is_remote ? root.get_parse_name() : (root.get_path() ?? uri);

                string? dev = (vol != null) ? vol.get_identifier("unix-device") : null;
                if (dev == null && root.get_path() != null) {
                    dev = get_device_for_mount_path(root.get_path());
                }
                string? backing = null;
                bool encrypted = (dev != null) ? check_is_encrypted(dev, out backing) : false;

                var item = new LocationItem(@"mount_$uri", name, cat, root, icon, subtitle);
                item.mount = m;
                item.volume = vol;
                item.drive = m.get_drive();
                item.is_mounted = true;
                item.can_eject = m.can_eject();
                item.can_unmount = m.can_unmount();
                item.is_encrypted = encrypted;
                item.encrypted_backing_device = backing;

                items.add(item);
            }

            // Unmounted Volumes
            var volumes = monitor.get_volumes();
            foreach (var v in volumes) {
                if (v.get_mount() != null) {
                    continue;
                }

                // If volume cannot be mounted without physical reconnection (e.g. ejected flash drive), do not show it
                if (!v.can_mount()) {
                    continue;
                }
                var drv = v.get_drive();
                if (drv != null && drv.is_media_removable() && !drv.has_media()) {
                    continue;
                }

                string? vol_id = v.get_identifier("uuid");
                if (vol_id == null) {
                    vol_id = v.get_name();
                }
                if (vol_id in seen_volume_ids) {
                    continue;
                }

                Icon? icon = v.get_symbolic_icon();
                if (icon == null) {
                    icon = v.get_icon();
                }
                if (icon == null) {
                    icon = new ThemedIcon("drive-harddisk-symbolic");
                }

                string? dev = v.get_identifier("unix-device");
                string? backing = null;
                bool encrypted = (dev != null) ? check_is_encrypted(dev, out backing) : false;
                if (!encrypted && v.get_name().down().contains("encrypted")) {
                    encrypted = true;
                    backing = dev;
                }

                string subtitle = encrypted ? "(Encrypted • Locked)" : "(Not mounted)";

                var item = new LocationItem(@"volume_$vol_id", v.get_name(), LocationCategory.DEVICE, null, icon, subtitle);
                item.volume = v;
                item.drive = v.get_drive();
                item.is_mounted = false;
                item.can_eject = v.can_eject() || (v.get_drive() != null && v.get_drive().can_eject());
                item.can_unmount = false;
                item.is_encrypted = encrypted;
                item.encrypted_backing_device = backing;

                items.add(item);
            }

            // 2. Standard Places
            var home_file = File.new_for_path(Environment.get_home_dir());
            var home_item = new LocationItem("home", "Home", LocationCategory.PLACE, home_file, new ThemedIcon("user-home-symbolic"), "~");
            items.add(home_item);

            var trash_file = File.new_for_uri("trash:///");
            var trash_item = new LocationItem("trash", "Trash", LocationCategory.PLACE, trash_file, new ThemedIcon("user-trash-symbolic"), "trash:///");
            items.add(trash_item);

            // 3. Quick Action: Connect to Server
            var connect_item = new LocationItem("action_connect", "Connect to Server...", LocationCategory.ACTION, null, new ThemedIcon("network-server-symbolic"), "SFTP, FTP, SMB, WebDAV");
            items.add(connect_item);

            return items;
        }

        public async bool unmount_or_eject(LocationItem item, Gtk.Window? parent) {
            var mount_op = new Gtk.MountOperation(parent);
            bool unmounted_ok = false;
            try {
                if (item.mount != null) {
                    if (item.mount.can_unmount()) {
                        yield item.mount.unmount_with_operation(MountUnmountFlags.NONE, mount_op, null);
                        unmounted_ok = true;
                    } else if (item.mount.can_eject()) {
                        yield item.mount.eject_with_operation(MountUnmountFlags.NONE, mount_op, null);
                        unmounted_ok = true;
                    } else {
                        yield item.mount.unmount_with_operation(MountUnmountFlags.NONE, mount_op, null);
                        unmounted_ok = true;
                    }
                } else if (item.volume != null && item.volume.can_eject()) {
                    yield item.volume.eject_with_operation(MountUnmountFlags.NONE, mount_op, null);
                    unmounted_ok = true;
                } else if (item.drive != null && item.drive.can_eject()) {
                    yield item.drive.eject_with_operation(MountUnmountFlags.NONE, mount_op, null);
                    unmounted_ok = true;
                }
            } catch (Error e) {
                warning("Failed to unmount/eject %s: %s", item.name, e.message);
                return false;
            }

            // If encrypted, lock the LUKS container
            if (item.is_encrypted && item.encrypted_backing_device != null) {
                yield lock_encrypted_container(item.encrypted_backing_device);
            }

            return unmounted_ok;
        }

        public static string? get_device_for_mount_path(string mount_path) {
            try {
                string contents;
                FileUtils.get_contents("/proc/mounts", out contents);
                var lines = contents.split("\n");
                foreach (var line in lines) {
                    if (line.strip().length == 0) continue;
                    var parts = line.split(" ");
                    if (parts.length >= 2) {
                        string mp = parts[1].replace("\\040", " ");
                        if (mp == mount_path) {
                            return parts[0];
                        }
                    }
                }
            } catch (Error e) {
                // ignore
            }
            return null;
        }

        public static string? get_mount_path_for_device(string device_node) {
            try {
                string contents;
                FileUtils.get_contents("/proc/mounts", out contents);
                var lines = contents.split("\n");
                foreach (var line in lines) {
                    if (line.strip().length == 0) continue;
                    var parts = line.split(" ");
                    if (parts.length >= 2 && parts[0] == device_node) {
                        return parts[1].replace("\\040", " ");
                    }
                }
            } catch (Error e) {
                // ignore
            }
            return null;
        }

        public static string? get_fs_type_for_mount_path(string mount_path) {
            try {
                string contents;
                FileUtils.get_contents("/proc/mounts", out contents);
                var lines = contents.split("\n");
                foreach (var line in lines) {
                    if (line.strip().length == 0) continue;
                    var parts = line.split(" ");
                    if (parts.length >= 3) {
                        string mp = parts[1].replace("\\040", " ");
                        if (mp == mount_path) {
                            return parts[2];
                        }
                    }
                }
            } catch (Error e) {
                // ignore
            }
            return null;
        }

        public static string? resolve_device_node(LocationItem item) {
            if (item.volume != null) {
                string? dev = item.volume.get_identifier("unix-device");
                if (dev != null && dev.length > 0) return dev;
            }
            if (item.mount != null) {
                var vol = item.mount.get_volume();
                if (vol != null) {
                    string? dev = vol.get_identifier("unix-device");
                    if (dev != null && dev.length > 0) return dev;
                }
                var root = item.mount.get_root();
                if (root != null && root.get_path() != null) {
                    string? dev = get_device_for_mount_path(root.get_path());
                    if (dev != null) return dev;
                }
            }
            if (item.file != null && item.file.get_path() != null) {
                string? dev = get_device_for_mount_path(item.file.get_path());
                if (dev != null) return dev;
            }
            return null;
        }

        public static string escape_udisks_path(string name) {
            var sb = new StringBuilder();
            for (int i = 0; i < name.length; i++) {
                char c = name[i];
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') {
                    sb.append_c(c);
                } else {
                    sb.append_printf("_%02x", (uint) c);
                }
            }
            return sb.str;
        }

        public static string get_udisks_block_path(string device_node) {
            string base_name = Path.get_basename(device_node);
            return "/org/freedesktop/UDisks2/block_devices/" + escape_udisks_path(base_name);
        }

        public static bool check_is_encrypted(string device_node, out string? backing_device) {
            backing_device = null;
            if (device_node.length == 0) return false;

            string base_name = Path.get_basename(device_node);

            // 1. Check if it's an unlocked cleartext dm-crypt device in sysfs
            string dm_uuid_path = @"/sys/class/block/$base_name/dm/uuid";
            if (FileUtils.test(dm_uuid_path, FileTest.EXISTS)) {
                try {
                    string content;
                    FileUtils.get_contents(dm_uuid_path, out content);
                    if (content.strip().has_prefix("CRYPT-")) {
                        string slaves_dir = @"/sys/class/block/$base_name/slaves";
                        try {
                            var dir = Dir.open(slaves_dir);
                            string? entry = null;
                            while ((entry = dir.read_name()) != null) {
                                if (entry.length > 0 && !entry.has_prefix(".")) {
                                    backing_device = "/dev/" + entry;
                                    return true;
                                }
                            }
                        } catch (Error e) {
                            // ignore
                        }
                        backing_device = device_node;
                        return true;
                    }
                } catch (Error e) {
                    // ignore
                }
            }

            // 2. Check if it's a locked LUKS container
            try {
                var bus = Bus.get_sync(BusType.SYSTEM, null);
                string udisks_path = get_udisks_block_path(device_node);
                var res = bus.call_sync(
                    "org.freedesktop.UDisks2",
                    udisks_path,
                    "org.freedesktop.DBus.Properties",
                    "Get",
                    new Variant("(ss)", "org.freedesktop.UDisks2.Block", "IdType"),
                    new VariantType("(v)"),
                    DBusCallFlags.NONE,
                    500,
                    null
                );
                Variant inner;
                res.get("(v)", out inner);
                string id_type = inner.get_string();
                if (id_type == "crypto_LUKS") {
                    backing_device = device_node;
                    return true;
                }
            } catch (Error e) {
                // ignore
            }

            return false;
        }

        public static async bool lock_encrypted_container(string backing_device_node) {
            try {
                var bus = yield Bus.get(BusType.SYSTEM, null);
                string udisks_path = get_udisks_block_path(backing_device_node);
                yield bus.call(
                    "org.freedesktop.UDisks2",
                    udisks_path,
                    "org.freedesktop.UDisks2.Encrypted",
                    "Lock",
                    new Variant.tuple(new Variant[] {
                        new Variant.array(new VariantType("{sv}"), new Variant[] {})
                    }),
                    null,
                    DBusCallFlags.NONE,
                    15000,
                    null
                );
                return true;
            } catch (Error e) {
                warning("Failed to lock encrypted device %s: %s", backing_device_node, e.message);
                return false;
            }
        }

        public async File? mount_volume(LocationItem item, Gtk.Window? parent) throws Error {
            if (item.volume == null) {
                return item.file;
            }
            var mount_op = new Gtk.MountOperation(parent);
            yield item.volume.mount(MountMountFlags.NONE, mount_op, null);
            var m = item.volume.get_mount();
            if (m != null) {
                return m.get_root();
            }
            return null;
        }
    }
}
