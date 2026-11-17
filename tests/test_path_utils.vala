namespace VCommander.Tests {

    public class PathUtilsTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("path.names", "Validate child names and reject ., .., slash", (ctx) => {
                run_names(ctx);
            });
            registry.add("path.ancestry", "Compare same/descendant paths at component boundaries", (ctx) => {
                run_ancestry(ctx);
            });
            registry.add("path.archive_sanitize", "Normalize archive members and reject traversal", (ctx) => {
                run_archive_sanitize(ctx);
            });
            registry.add("path.unicode", "Truncate and suffix UTF-8 strings by characters", (ctx) => {
                run_unicode(ctx);
            });
        }

        private static void run_names(TestContext ctx) {
            try {
                if (!ctx.expect(PathUtils.is_valid_child_name("file.txt"), "normal name accepted")) return;
                if (!ctx.expect(!PathUtils.is_valid_child_name("."), "'.' rejected")) return;
                if (!ctx.expect(!PathUtils.is_valid_child_name(".."), "'..' rejected")) return;
                if (!ctx.expect(!PathUtils.is_valid_child_name("a/b"), "slash rejected")) return;
                if (!ctx.expect(!PathUtils.is_valid_child_name(""), "empty rejected")) return;
            } finally {
                ctx.finish();
            }
        }

        private static void run_ancestry(TestContext ctx) {
            try {
                var base_dir = File.new_for_path("/tmp/vcmd-path-test");
                if (!ctx.expect(PathUtils.is_same_or_descendant(base_dir, base_dir), "same path is descendant")) return;
                if (!ctx.expect(PathUtils.is_same_or_descendant(base_dir, File.new_for_path("/tmp/vcmd-path-test/child")), "child is descendant")) return;
                if (!ctx.expect(!PathUtils.is_same_or_descendant(base_dir, File.new_for_path("/tmp/vcmd-path-tester")), "prefix-only path is not descendant")) return;
                if (!ctx.expect(!PathUtils.is_same_or_descendant(base_dir, File.new_for_path("/tmp/other")), "sibling is not descendant")) return;
            } finally {
                ctx.finish();
            }
        }

        private static void run_archive_sanitize(TestContext ctx) {
            try {
                if (!ctx.expect(PathUtils.sanitize_archive_member("a/../b") == null, "parent traversal rejected")) return;
                if (!ctx.expect(PathUtils.sanitize_archive_member("/a/b") == "a/b", "absolute path normalized")) return;
                if (!ctx.expect(PathUtils.sanitize_archive_member("./a/b") == "a/b", "dot component normalized")) return;
                if (!ctx.expect(PathUtils.sanitize_archive_member("") == null, "empty member rejected")) return;
                if (!ctx.expect(PathUtils.storage_safe_path("../../evil") == "evil", "storage path drops traversal")) return;
            } finally {
                ctx.finish();
            }
        }

        private static void run_unicode(TestContext ctx) {
            try {
                string value = "Hello, \u4e16\u754c!";
                if (!ctx.expect(PathUtils.truncate_chars(value, 5) == "Hello", "UTF-8 prefix")) return;
                if (!ctx.expect(PathUtils.suffix_chars(value, 2) == "\u754c!", "UTF-8 suffix")) return;
                if (!ctx.expect(PathUtils.truncate_chars("abc", 10) == "abc", "short string unchanged")) return;
            } finally {
                ctx.finish();
            }
        }
    }
}
