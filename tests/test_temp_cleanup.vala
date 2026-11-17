namespace VCommander.Tests {

    public class TempCleanupTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("temp.legacy_symlink_cleanup", "Legacy /tmp/vcmd-$UID symlink is not deleted through", (ctx) => {
                run_legacy_symlink(ctx);
            });
            registry.add("temp.secure_root", "Secure temp root is a real user-owned 0700 directory", (ctx) => {
                run_secure_root(ctx);
            });
        }

        private static void run_legacy_symlink(TestContext ctx) {
            string target = "";
            string legacy = "";
            try {
                target = TestFs.create_temp_root();
                TestFs.write_text(Path.build_filename(target, "keep.txt"), "keep");
                legacy = Path.build_filename(Environment.get_tmp_dir(), @"vcmd-$((int)Posix.getuid())");
                try {
                    if (FileUtils.test(legacy, FileTest.EXISTS)) {
                        ctx.skip("legacy temp path already exists");
                        return;
                    }
                    var link = File.new_for_path(legacy);
                    link.make_symbolic_link(target, null);
                } catch (Error e) {
                    ctx.skip(@"cannot create legacy symlink: $(e.message)");
                    return;
                }

                ArchiveTreeService.clean_temporary_directories();

                if (!ctx.expect(TestFs.exists(Path.build_filename(target, "keep.txt")), "symlink target preserved")) return;
                Posix.Stat st;
                if (!ctx.expect(Posix.lstat(legacy, out st) == 0 && Posix.S_ISLNK(st.st_mode), "symlink itself left untouched")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (legacy.length > 0) {
                    try { File.new_for_path(legacy).delete(null); } catch (Error e) {}
                }
                if (target.length > 0) TestFs.remove_tree(target);
                ctx.finish();
            }
        }

        private static void run_secure_root(TestContext ctx) {
            try {
                string root = ArchiveTreeService.get_secure_tmp_dir();
                Posix.Stat st;
                if (!ctx.expect(Posix.lstat(root, out st) == 0, "secure root exists")) return;
                if (!ctx.expect(Posix.S_ISDIR(st.st_mode), "secure root is a directory")) return;
                if (!ctx.expect((st.st_mode & 0777) == 0700, "secure root mode is 0700")) return;
                if (!ctx.expect(st.st_uid == (Posix.uid_t) Posix.getuid(), "secure root owned by current user")) return;
            } finally {
                ArchiveTreeService.clean_temporary_directories();
                ctx.finish();
            }
        }
    }
}
