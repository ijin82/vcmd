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

    public class ExtFSBindingRule : Object {
        public string helper_name { get; construct set; }
        public string? shell_pattern { get; construct set; default = null; }
        public Regex? regex_pattern { get; construct set; default = null; }
        public bool ignore_case { get; construct set; default = true; }

        public ExtFSBindingRule(string helper_name, string? shell_pattern, Regex? regex_pattern, bool ignore_case = true) {
            Object(
                helper_name: helper_name,
                shell_pattern: shell_pattern,
                regex_pattern: regex_pattern,
                ignore_case: ignore_case
            );
        }

        public bool matches(string filename) {
            string base_name = Path.get_basename(filename);
            if (shell_pattern != null && shell_pattern.length > 0) {
                if (shell_pattern.has_prefix(".")) {
                    if (ignore_case) {
                        if (base_name.down().has_suffix(shell_pattern.down())) return true;
                    } else {
                        if (base_name.has_suffix(shell_pattern)) return true;
                    }
                } else {
                    string pat = shell_pattern.contains("*") || shell_pattern.contains("?") ?
                        shell_pattern : "*" + shell_pattern;
                    var ps = new PatternSpec(ignore_case ? pat.down() : pat);
                    if (ps.match_string(ignore_case ? base_name.down() : base_name)) return true;
                }
            }
            if (regex_pattern != null) {
                if (regex_pattern.match(base_name)) return true;
            }
            return false;
        }
    }

    public class ArchiverRegistry : Object {
        private static ArchiverRegistry? instance = null;

        private GenericSet<string> available_tools;
        private GenericArray<ArchiveFormatInfo> pack_formats;
        private GenericArray<ExtFSHelperInfo> extfs_helpers;
        private GenericArray<ExtFSBindingRule> extfs_rules;

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
            extfs_rules = new GenericArray<ExtFSBindingRule>();

            detect_system_tools();
            detect_extfs_helpers();
            load_extfs_rules();
            initialize_pack_formats();
        }

        public void rescan() {
            available_tools.remove_all();
            pack_formats = new GenericArray<ArchiveFormatInfo>();
            extfs_helpers = new GenericArray<ExtFSHelperInfo>();
            extfs_rules = new GenericArray<ExtFSBindingRule>();

            detect_system_tools();
            detect_extfs_helpers();
            load_extfs_rules();
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

        public GenericArray<ExtFSBindingRule> get_extfs_rules() {
            return extfs_rules;
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

        public bool is_extfs_archive(string filename) {
            return get_extfs_helper_name_for_filename(filename) != null;
        }

        public ExtFSHelperInfo? get_extfs_helper_for_archive(string filename) {
            string? helper_name = get_extfs_helper_name_for_filename(filename);
            if (helper_name != null) {
                return find_extfs_helper(helper_name);
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
                lower.has_suffix(".gz") ||
                lower.has_suffix(".bz2") ||
                lower.has_suffix(".xz") ||
                lower.has_suffix(".zst")) {
                return true;
            }
            if (is_extfs_archive(filename)) {
                return true;
            }
            return false;
        }

        public string? get_extfs_helper_name_for_filename(string filename) {
            // 1. Check loaded rules (from user & system ini + fallbacks)
            for (uint i = 0; i < extfs_rules.length; i++) {
                var rule = extfs_rules.get(i);
                if (rule.matches(filename)) {
                    if (find_extfs_helper(rule.helper_name) != null) {
                        return rule.helper_name;
                    }
                }
            }

            // 2. Direct match with user plugin names:
            // e.g. ~/.config/vcmd/extfs/myarch matches *.myarch
            for (uint i = 0; i < extfs_helpers.length; i++) {
                var h = extfs_helpers.get(i);
                if (h.is_user_plugin) {
                    string ext = "." + h.name.down();
                    if (filename.down().has_suffix(ext)) {
                        return h.name;
                    }
                }
            }

            // 3. Fallbacks for zip and 7z when native CLI tools are absent
            string lower = filename.down();
            if (lower.has_suffix(".zip") && !has_tool("unzip") && !has_tool("7z") && !has_tool("7zz")) {
                if (find_extfs_helper("uzip") != null) return "uzip";
            }
            if (lower.has_suffix(".7z") && !has_tool("7z") && !has_tool("7zz")) {
                if (find_extfs_helper("u7z") != null) return "u7z";
            }

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
            // 1. Check user config directory (~/.config/vcmd/extfs)
            string user_extfs_dir = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "extfs");
            var user_dir = File.new_for_path(user_extfs_dir);
            if (!user_dir.query_exists()) {
                try {
                    user_dir.make_directory_with_parents(null);
                } catch (Error ignored) {}
            }
            scan_extfs_directory(user_extfs_dir, true);

            // 2. Check MC user extfs directory (~/.local/share/mc/extfs.d)
            string mc_user_extfs_dir = Path.build_filename(Environment.get_user_data_dir(), "mc", "extfs.d");
            scan_extfs_directory(mc_user_extfs_dir, true);

            // 3. System ExtFS directories (from Midnight Commander)
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

        private void load_extfs_rules() {
            // 1. User config in vcmd (~/.config/vcmd/extfs.ini)
            string user_vcmd_ini = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "extfs.ini");
            load_rules_from_ini(user_vcmd_ini);

            // 2. User MC config (~/.config/mc/mc.ext.ini)
            string user_mc_ini = Path.build_filename(Environment.get_user_config_dir(), "mc", "mc.ext.ini");
            load_rules_from_ini(user_mc_ini);

            // 3. System MC config (/etc/mc/mc.ext.ini)
            load_rules_from_ini("/etc/mc/mc.ext.ini");

            // 4. Built-in fallback rules
            load_default_fallback_rules();
        }

        private void load_rules_from_ini(string file_path) {
            var file = File.new_for_path(file_path);
            if (!file.query_exists()) return;

            var kf = new KeyFile();
            try {
                kf.load_from_file(file_path, KeyFileFlags.NONE);
            } catch (Error e) {
                return;
            }

            string[] groups = kf.get_groups();
            foreach (string g in groups) {
                try {
                    if (!kf.has_key(g, "Open")) continue;
                    string open_val = kf.get_string(g, "Open");
                    int p = open_val.index_of("%p/");
                    if (p < 0) continue;
                    string after = open_val.substring(p + 3);
                    int colon = after.index_of("://");
                    if (colon <= 0) continue;
                    string helper_name = after.substring(0, colon);
                    if (helper_name.has_suffix("+")) {
                        helper_name = helper_name.substring(0, helper_name.length - 1);
                    }

                    string? shell_pat = null;
                    if (kf.has_key(g, "Shell")) {
                        shell_pat = kf.get_string(g, "Shell").strip();
                    }

                    string? regex_pat = null;
                    if (kf.has_key(g, "Regex")) {
                        regex_pat = kf.get_string(g, "Regex").strip();
                    }

                    bool ignore_case = true;
                    if (kf.has_key(g, "ShellIgnoreCase")) {
                        ignore_case = kf.get_boolean(g, "ShellIgnoreCase");
                    } else if (kf.has_key(g, "RegexIgnoreCase")) {
                        ignore_case = kf.get_boolean(g, "RegexIgnoreCase");
                    }

                    Regex? rx = null;
                    if (regex_pat != null && regex_pat.length > 0) {
                        try {
                            RegexCompileFlags flags = RegexCompileFlags.OPTIMIZE;
                            if (ignore_case) flags |= RegexCompileFlags.CASELESS;
                            rx = new Regex(regex_pat, flags);
                        } catch (RegexError ignored) {}
                    }

                    if (shell_pat != null || rx != null) {
                        extfs_rules.add(new ExtFSBindingRule(helper_name, shell_pat, rx, ignore_case));
                    }
                } catch (Error ignored) {}
            }
        }

        private void load_default_fallback_rules() {
            string[,] fallbacks = {
                { "deb", ".deb" },
                { "deb", ".udeb" },
                { "deb", ".ipk" },
                { "rpm", ".rpm" },
                { "rpm", ".srpm" },
                { "rpm", ".spm" },
                { "iso9660", ".iso" },
                { "iso9660", ".img" },
                { "urar", ".rar" },
                { "ucab", ".cab" },
                { "uarj", ".arj" },
                { "ulha", ".lha" },
                { "ulha", ".lzh" },
                { "uace", ".ace" },
                { "uzoo", ".zoo" },
                { "uha", ".ha" },
                { "ualz", ".alz" },
                { "uarc", ".arc" },
                { "udar", ".dar" },
                { "uwim", ".wim" },
                { "trpm", ".trpm" },
                { "uar", ".a" },
                { "uar", ".lib" }
            };

            for (int i = 0; i < fallbacks.length[0]; i++) {
                string helper = fallbacks[i, 0];
                string ext = fallbacks[i, 1];
                extfs_rules.add(new ExtFSBindingRule(helper, ext, null, true));
            }

            try {
                extfs_rules.add(new ExtFSBindingRule("urar", null, new Regex("\\.r[0-9][0-9]$", RegexCompileFlags.CASELESS | RegexCompileFlags.OPTIMIZE), true));
                extfs_rules.add(new ExtFSBindingRule("uarj", null, new Regex("\\.a[0-9][0-9]$", RegexCompileFlags.CASELESS | RegexCompileFlags.OPTIMIZE), true));
            } catch (RegexError ignored) {}
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
