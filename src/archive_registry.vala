namespace VCommander {

    public enum ArchiveCompressionLevel {
        STORE = 0,
        FAST = 1,
        NORMAL = 6,
        MAXIMUM = 9,
        ULTRA = 10;

        public string to_display_string() {
            switch (this) {
                case STORE: return "Store (No Compression)";
                case FAST: return "Fast";
                case NORMAL: return "Normal (Default)";
                case MAXIMUM: return "Maximum";
                case ULTRA: return "Ultra";
                default: return "Normal";
            }
        }
    }

    public class ArchiveFormatInfo : Object {
        public string id { get; construct set; }
        public string name { get; construct set; }
        public string primary_extension { get; construct set; }
        public string mime_type { get; construct set; }
        public bool supports_password { get; construct set; default = false; }
        public bool supports_compression_level { get; construct set; default = true; }
        public string default_tool { get; construct set; default = ""; }
        public bool is_available { get; construct set; default = false; }

        public ArchiveFormatInfo(string id, string name, string primary_extension, string mime_type, bool supports_password, bool supports_compression_level, string default_tool, bool is_available) {
            Object(
                id: id,
                name: name,
                primary_extension: primary_extension,
                mime_type: mime_type,
                supports_password: supports_password,
                supports_compression_level: supports_compression_level,
                default_tool: default_tool,
                is_available: is_available
            );
        }
    }

    public class ExtFSHelperInfo : Object {
        public string name { get; construct set; }
        public string script_path { get; construct set; }
        public bool is_user_plugin { get; construct set; default = false; }

        public ExtFSHelperInfo(string name, string script_path, bool is_user_plugin) {
            Object(name: name, script_path: script_path, is_user_plugin: is_user_plugin);
        }
    }

    public class ArchiverRegistry : Object {
        private static ArchiverRegistry? instance = null;

        private GenericSet<string> available_tools;
        private GenericArray<ArchiveFormatInfo> pack_formats;
        private GenericArray<ExtFSHelperInfo> extfs_helpers;

        public static ArchiverRegistry get_instance() {
            if (instance == null) {
                instance = new ArchiverRegistry();
            }
            return instance;
        }

        private ArchiverRegistry() {
            available_tools = new GenericSet<string>(str_hash, str_equal);
            pack_formats = new GenericArray<ArchiveFormatInfo>();
            extfs_helpers = new GenericArray<ExtFSHelperInfo>();

            detect_system_tools();
            detect_extfs_helpers();
            initialize_pack_formats();
        }

        public void rescan() {
            available_tools.remove_all();
            pack_formats = new GenericArray<ArchiveFormatInfo>();
            extfs_helpers = new GenericArray<ExtFSHelperInfo>();

            detect_system_tools();
            detect_extfs_helpers();
            initialize_pack_formats();
        }

        public bool has_tool(string binary_name) {
            return available_tools.contains(binary_name);
        }

        public string? get_tool_path(string binary_name) {
            if (!available_tools.contains(binary_name)) return null;
            return Environment.find_program_in_path(binary_name);
        }

        public GenericArray<ArchiveFormatInfo> get_available_pack_formats() {
            var result = new GenericArray<ArchiveFormatInfo>();
            for (uint i = 0; i < pack_formats.length; i++) {
                var f = pack_formats.get(i);
                if (f.is_available) {
                    result.add(f);
                }
            }
            return result;
        }

        public ArchiveFormatInfo? find_format_by_id(string format_id) {
            for (uint i = 0; i < pack_formats.length; i++) {
                var f = pack_formats.get(i);
                if (f.id == format_id) {
                    return f;
                }
            }
            return null;
        }

        public ArchiveFormatInfo? find_format_by_extension(string extension) {
            string ext = extension.has_prefix(".") ? extension.down() : "." + extension.down();
            for (uint i = 0; i < pack_formats.length; i++) {
                var f = pack_formats.get(i);
                if (f.primary_extension.down() == ext) {
                    return f;
                }
            }
            return null;
        }

        public GenericArray<ExtFSHelperInfo> get_extfs_helpers() {
            return extfs_helpers;
        }

        public ExtFSHelperInfo? find_extfs_helper(string name) {
            for (uint i = 0; i < extfs_helpers.length; i++) {
                var h = extfs_helpers.get(i);
                if (h.name == name) {
                    return h;
                }
            }
            return null;
        }

        public bool is_archive_filename(string filename) {
            string lower = filename.down();
            if (lower.has_suffix(".zip") ||
                lower.has_suffix(".tar") ||
                lower.has_suffix(".tar.gz") || lower.has_suffix(".tgz") ||
                lower.has_suffix(".tar.bz2") || lower.has_suffix(".tbz2") ||
                lower.has_suffix(".tar.xz") || lower.has_suffix(".txz") ||
                lower.has_suffix(".tar.zst") ||
                lower.has_suffix(".7z") ||
                lower.has_suffix(".rar") ||
                lower.has_suffix(".iso") ||
                lower.has_suffix(".deb") ||
                lower.has_suffix(".rpm") ||
                lower.has_suffix(".cab") ||
                lower.has_suffix(".arj") ||
                lower.has_suffix(".cpio") ||
                lower.has_suffix(".gz") ||
                lower.has_suffix(".bz2") ||
                lower.has_suffix(".xz") ||
                lower.has_suffix(".zst")) {
                return true;
            }
            return false;
        }

        public string? get_extfs_helper_name_for_filename(string filename) {
            string lower = filename.down();
            if (lower.has_suffix(".7z")) return "u7z";
            if (lower.has_suffix(".rar")) return "urar";
            if (lower.has_suffix(".iso")) return "iso9660";
            if (lower.has_suffix(".deb")) return "deb";
            if (lower.has_suffix(".rpm")) return "rpm";
            if (lower.has_suffix(".cab")) return "ucab";
            if (lower.has_suffix(".arj")) return "uarj";
            if (lower.has_suffix(".lha") || lower.has_suffix(".lzh")) return "ulha";
            if (lower.has_suffix(".ace")) return "uace";
            if (lower.has_suffix(".zoo")) return "uzoo";
            if (lower.has_suffix(".ha")) return "uha";
            if (lower.has_suffix(".alz")) return "ualz";
            if (lower.has_suffix(".arc")) return "uarc";
            if (lower.has_suffix(".dar")) return "udar";
            if (lower.has_suffix(".wim")) return "uwim";
            if (lower.has_suffix(".zip") && !has_tool("unzip") && !has_tool("7z") && !has_tool("7zz")) return "uzip";
            return null;
        }

        private void detect_system_tools() {
            string[] tool_names = {
                "tar",
                "zip",
                "unzip",
                "7z",
                "7zz",
                "7za",
                "gzip",
                "bzip2",
                "xz",
                "zstd",
                "rar",
                "unrar"
            };

            foreach (var tool in tool_names) {
                string? path = Environment.find_program_in_path(tool);
                if (path != null && path.length > 0) {
                    available_tools.add(tool);
                }
            }
        }

        private void detect_extfs_helpers() {
            // Check user config directory first (~/.config/vcmd/extfs)
            string user_extfs_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "extfs");
            scan_extfs_directory(user_extfs_dir, true);

            // System ExtFS directories (from Midnight Commander)
            string[] system_extfs_dirs = {
                "/usr/lib/mc/extfs.d",
                "/usr/libexec/mc/extfs.d",
                "/usr/local/libexec/mc/extfs.d",
                "/usr/local/lib/mc/extfs.d"
            };

            foreach (var dir in system_extfs_dirs) {
                scan_extfs_directory(dir, false);
            }
        }

        private void scan_extfs_directory(string dir_path, bool is_user_plugin) {
            var dir = File.new_for_path(dir_path);
            if (!dir.query_exists()) return;

            try {
                var enumerator = dir.enumerate_children(
                    "standard::name,standard::type,access::can-execute",
                    FileQueryInfoFlags.NONE
                );

                FileInfo? info = null;
                while ((info = enumerator.next_file()) != null) {
                    if (info.get_file_type() == FileType.REGULAR) {
                        string name = info.get_name();
                        if (name.has_prefix("README") || name.has_suffix(".diff")) continue;

                        bool can_exec = info.get_attribute_boolean("access::can-execute");
                        if (can_exec) {
                            string full_path = Path.build_filename(dir_path, name);
                            // Avoid duplicates (user plugin overrides system plugin)
                            if (find_extfs_helper(name) == null) {
                                extfs_helpers.add(new ExtFSHelperInfo(name, full_path, is_user_plugin));
                            }
                        }
                    }
                }
            } catch (Error e) {
                // Non-critical, directory might not be readable
            }
        }

        private void initialize_pack_formats() {
            bool has_tar = has_tool("tar");
            bool has_gzip = has_tool("gzip");
            bool has_xz = has_tool("xz");
            bool has_zstd = has_tool("zstd");
            bool has_bzip2 = has_tool("bzip2");
            bool has_zip = has_tool("zip");
            bool has_7z = has_tool("7z") || has_tool("7zz");

            // 1. ZIP (.zip)
            bool zip_available = has_zip || has_7z;
            string zip_tool = has_zip ? "zip" : (has_tool("7z") ? "7z" : "7zz");
            pack_formats.add(new ArchiveFormatInfo(
                "zip",
                "ZIP Archive (.zip)",
                ".zip",
                "application/zip",
                true,   // supports encryption/password
                true,   // supports compression levels 0..9
                zip_tool,
                zip_available
            ));

            // 2. Gzip Tarball (.tar.gz)
            bool tar_gz_available = has_tar && has_gzip;
            pack_formats.add(new ArchiveFormatInfo(
                "tar.gz",
                "Gzip Tarball (.tar.gz)",
                ".tar.gz",
                "application/gzip",
                false,
                true,
                "tar",
                tar_gz_available
            ));

            // 3. 7-Zip Archive (.7z)
            string p7z_tool = has_tool("7z") ? "7z" : (has_tool("7zz") ? "7zz" : "7za");
            pack_formats.add(new ArchiveFormatInfo(
                "7z",
                "7-Zip Archive (.7z)",
                ".7z",
                "application/x-7z-compressed",
                true,   // supports encryption/password
                true,   // supports compression levels
                p7z_tool,
                has_7z
            ));

            // 4. XZ Tarball (.tar.xz)
            bool tar_xz_available = has_tar && has_xz;
            pack_formats.add(new ArchiveFormatInfo(
                "tar.xz",
                "XZ Tarball (.tar.xz)",
                ".tar.xz",
                "application/x-xz",
                false,
                true,
                "tar",
                tar_xz_available
            ));

            // 5. Zstandard Tarball (.tar.zst)
            bool tar_zst_available = has_tar && has_zstd;
            pack_formats.add(new ArchiveFormatInfo(
                "tar.zst",
                "Zstandard Tarball (.tar.zst)",
                ".tar.zst",
                "application/zstd",
                false,
                true,
                "tar",
                tar_zst_available
            ));

            // 6. Bzip2 Tarball (.tar.bz2)
            bool tar_bz2_available = has_tar && has_bzip2;
            pack_formats.add(new ArchiveFormatInfo(
                "tar.bz2",
                "Bzip2 Tarball (.tar.bz2)",
                ".tar.bz2",
                "application/x-bzip2",
                false,
                true,
                "tar",
                tar_bz2_available
            ));

            // 7. Tar Archive (.tar)
            pack_formats.add(new ArchiveFormatInfo(
                "tar",
                "Tar Archive (.tar)",
                ".tar",
                "application/x-tar",
                false,
                false,  // uncompressed
                "tar",
                has_tar
            ));
        }
    }
}
