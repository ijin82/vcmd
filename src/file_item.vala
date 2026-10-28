namespace VCommander {

    public class FileItem : Object {
        public File file { get; construct set; }
        public string name { get; construct set; }
        public string display_name { get; construct set; }
        public int64 size { get; construct set; default = 0; }
        public DateTime? mtime { get; construct set; default = null; }
        public bool is_dir { get; construct set; default = false; }
        public bool is_parent_dir { get; construct set; default = false; }
        public bool is_symlink { get; construct set; default = false; }
        public bool is_hidden { get; construct set; default = false; }
        public Icon? icon { get; construct set; default = null; }
        public string file_type { get; construct set; default = ""; }
        public string owner { get; construct set; default = ""; }
        public string group { get; construct set; default = ""; }
        public uint32 mode { get; construct set; default = 0; }

        public bool is_calculating_size { get; set; default = false; }
        public int64 custom_size { get; set; default = -1; }
        public bool is_tagged { get; set; default = false; }

        public string formatted_size {
            owned get {
                if (is_parent_dir) {
                    return "";
                }
                if (is_calculating_size) {
                    return "[Counting...]";
                }
                if (custom_size >= 0) {
                    return format_size(custom_size);
                }
                if (is_dir) {
                    return "<DIR>";
                }
                return format_size(size);
            }
        }

        public string formatted_mtime {
            owned get {
                if (is_parent_dir || mtime == null) {
                    return "";
                }
                return mtime.format("%Y-%m-%d %H:%M");
            }
        }

        public string formatted_permissions {
            owned get {
                if (is_parent_dir) {
                    return "";
                }
                if (mode == 0) {
                    return is_dir ? "drwxr-xr-x" : "-rw-r--r--";
                }

                var sb = new StringBuilder();

                // File type
                if (is_symlink) {
                    sb.append_c('l');
                } else if (is_dir) {
                    sb.append_c('d');
                } else if ((mode & 0170000) == 0060000) {
                    sb.append_c('b');
                } else if ((mode & 0170000) == 0020000) {
                    sb.append_c('c');
                } else if ((mode & 0170000) == 0010000) {
                    sb.append_c('p');
                } else if ((mode & 0170000) == 0140000) {
                    sb.append_c('s');
                } else {
                    sb.append_c('-');
                }

                // User permissions
                sb.append_c(((mode & 0400) != 0) ? 'r' : '-');
                sb.append_c(((mode & 0200) != 0) ? 'w' : '-');
                if ((mode & 04000) != 0) {
                    sb.append_c(((mode & 0100) != 0) ? 's' : 'S');
                } else {
                    sb.append_c(((mode & 0100) != 0) ? 'x' : '-');
                }

                // Group permissions
                sb.append_c(((mode & 0040) != 0) ? 'r' : '-');
                sb.append_c(((mode & 0020) != 0) ? 'w' : '-');
                if ((mode & 02000) != 0) {
                    sb.append_c(((mode & 0010) != 0) ? 's' : 'S');
                } else {
                    sb.append_c(((mode & 0010) != 0) ? 'x' : '-');
                }

                // Other permissions
                sb.append_c(((mode & 0004) != 0) ? 'r' : '-');
                sb.append_c(((mode & 0002) != 0) ? 'w' : '-');
                if ((mode & 01000) != 0) {
                    sb.append_c(((mode & 0001) != 0) ? 't' : 'T');
                } else {
                    sb.append_c(((mode & 0001) != 0) ? 'x' : '-');
                }

                return sb.str;
            }
        }

        public FileItem.for_parent(File parent_file) {
            Object(
                file: parent_file,
                name: "..",
                display_name: "..",
                size: 0,
                mtime: null,
                is_dir: true,
                is_parent_dir: true,
                is_hidden: false,
                icon: new ThemedIcon("go-up-symbolic"),
                file_type: "Folder",
                owner: "",
                group: "",
                mode: 0
            );
        }

        public FileItem(File file, FileInfo info) {
            bool dir = (info.get_file_type() == FileType.DIRECTORY);
            string item_name = info.get_name();
            string disp_name = info.get_display_name();
            int64 item_size = dir ? 0 : info.get_size();
            DateTime? mod_time = info.get_modification_date_time();
            bool hidden = info.get_is_hidden() || item_name.has_prefix(".");
            Icon? item_icon = info.get_icon();

            if (item_icon == null) {
                if (dir) {
                    item_icon = new ThemedIcon("folder-symbolic");
                } else {
                    item_icon = new ThemedIcon("text-x-generic-symbolic");
                }
            }

            string ftype = "";
            if (dir) {
                ftype = "Folder";
            } else {
                int dot_idx = item_name.last_index_of_char('.');
                if (dot_idx > 0 && dot_idx < item_name.length - 1) {
                    ftype = item_name.substring(dot_idx + 1).up();
                } else {
                    ftype = "File";
                }
            }

            bool symlink = info.get_is_symlink();

            string item_owner = "";
            string? o_user = info.get_attribute_string("owner::user");
            if (o_user != null && o_user.length > 0) {
                item_owner = o_user;
            } else {
                string? u_name = info.get_attribute_string("unix::user-name");
                if (u_name != null && u_name.length > 0) {
                    item_owner = u_name;
                } else if (info.has_attribute("unix::uid")) {
                    item_owner = info.get_attribute_uint32("unix::uid").to_string();
                }
            }

            string item_group = "";
            string? o_group = info.get_attribute_string("owner::group");
            if (o_group != null && o_group.length > 0) {
                item_group = o_group;
            } else {
                string? g_name = info.get_attribute_string("unix::group-name");
                if (g_name != null && g_name.length > 0) {
                    item_group = g_name;
                } else if (info.has_attribute("unix::gid")) {
                    item_group = info.get_attribute_uint32("unix::gid").to_string();
                }
            }

            uint32 item_mode = 0;
            if (info.has_attribute("unix::mode")) {
                item_mode = info.get_attribute_uint32("unix::mode");
            }

            Object(
                file: file,
                name: item_name,
                display_name: disp_name,
                size: item_size,
                mtime: mod_time,
                is_dir: dir,
                is_parent_dir: false,
                is_symlink: symlink,
                is_hidden: hidden,
                icon: item_icon,
                file_type: ftype,
                owner: item_owner,
                group: item_group,
                mode: item_mode
            );
        }

        public static int compare_by_name(FileItem a, FileItem b) {
            // Parent directory ".." always stays at the top
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            // Directories always first
            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            return a.display_name.collate(b.display_name);
        }

        public static int compare_by_type(FileItem a, FileItem b) {
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            // Directories always first
            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            if (a.is_dir && b.is_dir) {
                return a.display_name.collate(b.display_name);
            }

            int res = a.file_type.collate(b.file_type);
            if (res != 0) {
                return res;
            }
            return a.display_name.collate(b.display_name);
        }

        public static int compare_by_size(FileItem a, FileItem b) {
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            // Directories always first
            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            if (a.is_dir && b.is_dir) {
                return a.display_name.collate(b.display_name);
            }

            int64 effective_size_a = (a.custom_size >= 0) ? a.custom_size : a.size;
            int64 effective_size_b = (b.custom_size >= 0) ? b.custom_size : b.size;

            if (effective_size_a < effective_size_b) return -1;
            if (effective_size_a > effective_size_b) return 1;
            return a.display_name.collate(b.display_name);
        }

        public static int compare_by_mtime(FileItem a, FileItem b) {
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            // Directories always first
            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            int64 time_a = (a.mtime != null) ? a.mtime.to_unix() : 0;
            int64 time_b = (b.mtime != null) ? b.mtime.to_unix() : 0;

            if (time_a < time_b) return -1;
            if (time_a > time_b) return 1;
            return a.display_name.collate(b.display_name);
        }

        public static int compare_by_owner(FileItem a, FileItem b) {
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            int res = a.owner.collate(b.owner);
            if (res != 0) return res;
            return a.display_name.collate(b.display_name);
        }

        public static int compare_by_group(FileItem a, FileItem b) {
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            int res = a.group.collate(b.group);
            if (res != 0) return res;
            return a.display_name.collate(b.display_name);
        }

        public static int compare_by_permissions(FileItem a, FileItem b) {
            if (a.is_parent_dir) return -1;
            if (b.is_parent_dir) return 1;

            if (a.is_dir && !b.is_dir) return -1;
            if (!a.is_dir && b.is_dir) return 1;

            int res = a.formatted_permissions.collate(b.formatted_permissions);
            if (res != 0) return res;
            return a.display_name.collate(b.display_name);
        }
    }
}
