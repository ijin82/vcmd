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
                file_type: "Folder"
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
                file_type: ftype
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
    }
}
