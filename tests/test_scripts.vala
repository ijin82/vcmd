namespace VCommander.Tests {

    public class ScriptsTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("scripts.release_version", "Reject unsafe release versions before building", (ctx) => {
                run_release_version(ctx);
            });
        }

        private static async void run_release_version(TestContext ctx) {
            try {
                string script = Path.build_filename(Environment.get_current_dir(), "package-release.sh");
                if (!FileUtils.test(script, FileTest.EXISTS)) {
                    ctx.skip("package-release.sh not found in current directory");
                    return;
                }

                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string[] argv = { script, "bad/version" };
                var proc = launcher.spawnv(argv);
                string? stdout_text = null;
                string? stderr_text = null;
                yield proc.communicate_utf8_async(null, null, out stdout_text, out stderr_text);

                if (!ctx.expect(proc.get_if_exited(), "release script exited")) return;
                if (!ctx.expect(proc.get_exit_status() != 0, "unsafe version rejected")) return;
                string err = (stderr_text != null) ? stderr_text : "";
                if (!ctx.expect(err.contains("unsupported characters"), @"unexpected stderr: $err")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ctx.finish();
            }
        }
    }
}
