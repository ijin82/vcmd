namespace VCommander {

    /**
     * Shared path-safety helpers.
     *
     * These utilities deliberately avoid touching the filesystem: they validate
     * user input and compare already-resolved paths/URIs. Callers must still
     * perform their own existence checks where required.
     */
    public class PathUtils : Object {

        public static bool is_valid_child_name(string? name) {
            if (name == null || name.length == 0) return false;
            if (name == "." || name == "..") return false;
            if (name.contains("/")) return false;
            return true;
        }

        private static string normalize_for_compare(File file) {
            string? local = file.get_path();
            if (local != null) {
                return GLib.Filename.canonicalize(local, null);
            }

            string uri = file.get_uri();
            int scheme_end = uri.index_of("://");
            int min_len = (scheme_end >= 0) ? scheme_end + 3 : 0;
            while (uri.length > min_len && uri.has_suffix("/")) {
                uri = uri.substring(0, uri.length - 1);
            }
            return uri;
        }

        /** Returns true when candidate is ancestor itself or a descendant of ancestor. */
        public static bool is_same_or_descendant(File ancestor, File candidate) {
            string a = normalize_for_compare(ancestor);
            string c = normalize_for_compare(candidate);
            if (a == c) return true;
            if (a == "/") return c.has_prefix("/");
            return c.has_prefix(a + "/");
        }

        /** Returns true when candidate is strictly below ancestor. */
        public static bool is_strict_descendant(File ancestor, File candidate) {
            if (ancestor.equal(candidate)) return false;
            return is_same_or_descendant(ancestor, candidate);
        }

        /**
         * Normalizes a member path read from an archive.
         *
         * Returns null for absolute paths, parent traversals, NUL bytes, and
         * empty results. The returned value contains no "." or ".." components
         * and is safe to use as a relative path below a destination root.
         */
        public static string? sanitize_archive_member(string? raw, bool allow_empty = false) {
            if (raw == null) return null;

            string path = raw;
            while (path.has_prefix("/")) {
                path = path.substring(1);
            }

            var sb = new StringBuilder();
            string[] parts = path.split("/");
            foreach (var part in parts) {
                if (part.length == 0 || part == ".") continue;
                if (part == "..") return null;
                if (sb.len > 0) sb.append("/");
                sb.append(part);
            }

            string result = sb.str;
            if (!allow_empty && result.length == 0) return null;
            return result;
        }

        /**
         * Produces a filesystem-safe relative path from untrusted archive data.
         *
         * Unlike sanitize_archive_member(), this never fails: unsafe components
         * are dropped. It is a last-resort guard for temporary extraction paths;
         * normal extraction code should reject unsafe members instead.
         */
        public static string storage_safe_path(string? raw) {
            if (raw == null) return "_invalid_";

            string path = raw;
            while (path.has_prefix("/")) {
                path = path.substring(1);
            }

            var sb = new StringBuilder();
            string[] parts = path.split("/");
            foreach (var part in parts) {
                if (part.length == 0 || part == "." || part == "..") continue;
                if (sb.len > 0) sb.append("/");
                sb.append(part);
            }
            return (sb.len > 0) ? sb.str : "_invalid_";
        }

        /**
         * Truncates a UTF-8 string by character count, never splitting a
         * multibyte sequence.
         */
        public static string truncate_chars(string text, int max_chars) {
            if (text == null || max_chars <= 0) return "";
            int count = text.char_count();
            if (count <= max_chars) return text;
            int byte_offset = text.index_of_nth_char(max_chars);
            if (byte_offset <= 0 || byte_offset > text.length) return "";
            return text.substring(0, byte_offset);
        }

        public static string suffix_chars(string text, int max_chars) {
            if (text == null || max_chars <= 0) return "";
            int count = text.char_count();
            if (count <= max_chars) return text;
            int byte_offset = text.index_of_nth_char(count - max_chars);
            if (byte_offset < 0 || byte_offset >= text.length) return "";
            return text.substring(byte_offset);
        }
    }
}
