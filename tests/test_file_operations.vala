namespace VCommander.Tests {

    public class FileOperationsTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("fileops.copy_file", "Copy a regular file and verify its contents", (ctx) => {
                run_copy_file(ctx);
            });
            registry.add("fileops.copy_into_self", "Reject copying a directory into its own descendant", (ctx) => {
                run_copy_into_self(ctx);
            });
            registry.add("fileops.move_into_self", "Reject moving a directory into its own descendant", (ctx) => {
                run_move_into_self(ctx);
            });
            registry.add("fileops.delete_recursive_symlink", "Recursive delete removes a link but not its target", (ctx) => {
                run_delete_symlink(ctx);
            });
            registry.add("fileops.create_symlink", "Create a symbolic link and verify its type", (ctx) => {
                run_create_symlink(ctx);
            });
            registry.add("fileops.copy_dir_metadata", "Preserve directory permissions while copying", (ctx) => {
                run_copy_dir_metadata(ctx);
            });
            registry.add("fileops.cancel_preflight", "Checked existence helper propagates cancellation", (ctx) => {
                run_cancel_preflight(ctx);
            });
            registry.add("fileops.file_over_dir_skip", "Skip a file copy when the destination is a directory", (ctx) => {
                run_file_over_dir_skip(ctx);
            });
        }

        private static async void run_copy_file(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string source = Path.build_filename(root, "source.txt");
                string dest = Path.build_filename(root, "dest.txt");
                TestFs.write_text(source, "hello");
                yield FileOperationService.copy_file_or_dir(File.new_for_path(source), File.new_for_path(dest));
                if (!ctx.expect(TestFs.exists(dest), "destination exists")) return;
                if (!ctx.expect(TestFs.read_text(dest) == "hello", "destination content")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_copy_into_self(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string source = Path.build_filename(root, "source");
                DirUtils.create_with_parents(Path.build_filename(source, "sub"), 0755);
                string inner = Path.build_filename(source, "sub", "nested");
                try {
                    yield FileOperationService.copy_file_or_dir(File.new_for_path(source), File.new_for_path(inner));
                    ctx.fail("copy into self did not throw");
                    return;
                } catch (Error e) {
                    if (!ctx.expect(e.matches(IOError.quark(), IOError.INVALID_ARGUMENT), @"unexpected error: $(e.message)")) return;
                }
                if (!ctx.expect(!TestFs.exists(inner), "no nested destination created")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_move_into_self(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string source = Path.build_filename(root, "source");
                DirUtils.create_with_parents(Path.build_filename(source, "sub"), 0755);
                string inner = Path.build_filename(source, "sub", "nested");
                try {
                    yield FileOperationService.move_file_or_dir(File.new_for_path(source), File.new_for_path(inner));
                    ctx.fail("move into self did not throw");
                    return;
                } catch (Error e) {
                    if (!ctx.expect(e.matches(IOError.quark(), IOError.INVALID_ARGUMENT), @"unexpected error: $(e.message)")) return;
                }
                if (!ctx.expect(!TestFs.exists(inner), "no nested destination created")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_delete_symlink(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string dir = Path.build_filename(root, "dir");
                DirUtils.create_with_parents(dir, 0755);
                string outside = Path.build_filename(root, "outside.txt");
                TestFs.write_text(outside, "keep");
                string link = Path.build_filename(dir, "link");
                File.new_for_path(link).make_symbolic_link(outside, null);
                yield FileOperationService.delete_recursive(File.new_for_path(dir));
                if (!ctx.expect(!TestFs.exists(dir), "directory removed")) return;
                if (!ctx.expect(TestFs.exists(outside), "symlink target preserved")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_create_symlink(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string target = Path.build_filename(root, "target.txt");
                string link = Path.build_filename(root, "link.txt");
                TestFs.write_text(target, "target");
                yield FileOperationService.create_symbolic_link(File.new_for_path(link), target, false);
                var info = yield File.new_for_path(link).query_info_async(
                    FileAttribute.STANDARD_TYPE,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    Priority.DEFAULT,
                    null
                );
                if (!ctx.expect(info.get_file_type() == FileType.SYMBOLIC_LINK, "link has symlink type")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_copy_dir_metadata(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string source = Path.build_filename(root, "source");
                string dest = Path.build_filename(root, "dest");
                DirUtils.create_with_parents(source, 0750);
                Posix.chmod(source, 0750);
                TestFs.write_text(Path.build_filename(source, "file.txt"), "x");
                yield FileOperationService.copy_file_or_dir(File.new_for_path(source), File.new_for_path(dest));
                if (!ctx.expect(TestFs.mode(dest) == 0750, @"expected 0750, got $(TestFs.mode(dest).to_string())")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_cancel_preflight(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string path = Path.build_filename(root, "exists.txt");
                TestFs.write_text(path, "x");
                var cancellable = new Cancellable();
                cancellable.cancel();
                try {
                    yield FileOperationService.file_exists_checked_async(File.new_for_path(path), cancellable);
                    ctx.fail("cancelled existence check did not throw");
                    return;
                } catch (Error e) {
                    if (!ctx.expect(e.matches(IOError.quark(), IOError.CANCELLED), @"unexpected error: $(e.message)")) return;
                }
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }

        private static async void run_file_over_dir_skip(TestContext ctx) {
            string root = "";
            try {
                root = TestFs.create_temp_root();
                string source = Path.build_filename(root, "source.txt");
                string dest = Path.build_filename(root, "dest");
                TestFs.write_text(source, "source");
                DirUtils.create_with_parents(dest, 0755);
                TestFs.write_text(Path.build_filename(dest, "keep.txt"), "keep");
                var resolver = new SimpleConflictResolver(ConflictResolution.SKIP);
                yield FileOperationService.copy_file_or_dir(
                    File.new_for_path(source),
                    File.new_for_path(dest),
                    resolver
                );
                if (!ctx.expect(TestFs.exists(Path.build_filename(dest, "keep.txt")), "directory contents preserved")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                if (root.length > 0) TestFs.remove_tree(root);
                ctx.finish();
            }
        }
    }
}
