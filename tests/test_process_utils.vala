namespace VCommander.Tests {

    public class ProcessUtilsTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("process.stderr_drain", "Drain more stderr than a pipe buffer without deadlocking", (ctx) => {
                run_stderr_drain(ctx);
            });
        }

        private static async void run_stderr_drain(TestContext ctx) {
            try {
                var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                string[] argv = {
                    "sh",
                    "-c",
                    "i=0; while [ $i -lt 12000 ]; do echo stderr-line-$i >&2; i=$((i+1)); done"
                };
                var proc = launcher.spawnv(argv);

                var stream = new DataInputStream(proc.get_stderr_pipe());
                var capture = new StderrCapture();
                capture.read.begin(stream);

                yield proc.wait_check_async(null);
                yield capture.wait_done(3000);

                if (!ctx.expect(capture.done, "stderr reader completed")) return;
                if (!ctx.expect(capture.text.len > 0, "stderr text captured")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ctx.finish();
            }
        }
    }
}
