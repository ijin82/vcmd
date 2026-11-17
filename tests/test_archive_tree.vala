namespace VCommander.Tests {

    public class ArchiveTreeTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("archive.reject_unsafe_entry", "ArchiveTree rejects parent traversal entries", (ctx) => {
                run_reject_unsafe(ctx);
            });
            registry.add("archive.temp_path_contained", "Preview path remains below the secure temp root", (ctx) => {
                run_temp_contained(ctx);
            });
            registry.add("archive.list_tar", "List a real tar archive through ArchiveTreeService", (ctx) => {
                run_list_tar(ctx);
            });
            registry.add("archive.list_zip", "List a real zip archive through ArchiveTreeService", (ctx) => {
                run_list_zip(ctx);
            });
        }

        private static void run_reject_unsafe(TestContext ctx) {
            try {
                var tree = new ArchiveTree("/tmp/test.zip", 0);
                tree.add_entry(new ArchiveEntry(
                    "../escape.txt",
                    "escape.txt",
                    false,
                    1,
                    null,
                    0,
                    "",
                    ""
                ));
                tree.add_entry(new ArchiveEntry(
                    "dir/../inside.txt",
                    "inside.txt",
                    false,
                    1,
                    null,
                    0,
                    "",
                    ""
                ));
                tree.add_entry(new ArchiveEntry(
                    "safe/file.txt",
                    "file.txt",
                    false,
                    1,
                    null,
                    0,
                    "",
                    ""
                ));
                if (!ctx.expect(tree.find_node("escape.txt") == null, "traversal entry not added")) return;
                var safe = tree.find_node("safe/file.txt");
                if (!ctx.expect(safe != null, "safe entry added")) return;
            } finally {
                ctx.finish();
            }
        }

        private static void run_temp_contained(TestContext ctx) {
            try {
                string root = ArchiveTreeService.get_preview_root_dir();
                var candidate = ArchiveTreeService.get_temp_extracted_file(
                    "/tmp/example.zip",
                    "../../outside.txt"
                );
                if (!ctx.expect(PathUtils.is_same_or_descendant(File.new_for_path(root), candidate), "preview path stays under root")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ArchiveTreeService.clean_temporary_directories();
                ctx.finish();
            }
        }

        private static async void run_list_tar(TestContext ctx) {
            string root = "";
            try {
                if (Environment.find_program_in_path("tar") == null) {
                    ctx.skip("tar is not installed");
                    return;
                }
                root = TestFs.create_temp_root();
                string src_dir = Path.build_filename(root, "src");
                string archive = Path.build_filename(root, "sample.tar");
                DirUtils.create_with_parents(src_dir, 0755);
                TestFs.write_text(Path.build_filename(src_dir, "file.txt"), "archive content");

                string[] argv = { "tar", "-cf", archive, "-C", src_dir, "file.txt" };
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                var proc = launcher.spawnv(argv);
                yield proc.wait_check_async(null);

                var tree = yield ArchiveTreeService.get_tree(archive, null);
                var items = ArchiveTreeService.list_directory(tree, "", File.new_for_path(src_dir));
                bool found = false;
                for (uint i = 0; i < items.length; i++) {
                    if (items.get(i).name == "file.txt") found = true;
                }
                if (!ctx.expect(found, "tar entry listed")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ArchiveTreeService.clear_cache();
                if (root.length > 0) TestFs.remove_tree(root);
                ArchiveTreeService.clean_temporary_directories();
                ctx.finish();
            }
        }

        private static async void run_list_zip(TestContext ctx) {
            string root = "";
            try {
                if (Environment.find_program_in_path("zip") == null) {
                    ctx.skip("zip is not installed");
                    return;
                }
                root = TestFs.create_temp_root();
                string src_dir = Path.build_filename(root, "src");
                string archive = Path.build_filename(root, "sample.zip");
                DirUtils.create_with_parents(src_dir, 0755);
                TestFs.write_text(Path.build_filename(src_dir, "file.txt"), "archive content");

                string[] argv = { "zip", "-q", "-r", archive, "file.txt" };
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                launcher.set_cwd(src_dir);
                var proc = launcher.spawnv(argv);
                yield proc.wait_check_async(null);

                var tree = yield ArchiveTreeService.get_tree(archive, null);
                var items = ArchiveTreeService.list_directory(tree, "", File.new_for_path(src_dir));
                bool found = false;
                for (uint i = 0; i < items.length; i++) {
                    if (items.get(i).name == "file.txt") found = true;
                }
                if (!ctx.expect(found, "zip entry listed")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ArchiveTreeService.clear_cache();
                if (root.length > 0) TestFs.remove_tree(root);
                ArchiveTreeService.clean_temporary_directories();
                ctx.finish();
            }
        }
    }
}
