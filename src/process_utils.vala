namespace VCommander {

    /**
     * Drains a process stderr stream concurrently with the caller's work.
     *
     * Subprocesses that write more than the pipe buffer must be drained while
     * they run; waiting first and reading afterwards can deadlock.
     */
    public class StderrCapture : Object {
        private const int MAX_BYTES = 64 * 1024;

        public StringBuilder text;
        public bool done;

        public StderrCapture() {
            text = new StringBuilder();
            done = false;
        }

        public async void read(DataInputStream stream) {
            try {
                size_t length;
                string? line;
                while ((line = yield stream.read_line_utf8_async(Priority.DEFAULT, null, out length)) != null) {
                    if (text.len < MAX_BYTES) {
                        text.append(line);
                        text.append("\n");
                    }
                }
            } catch (Error e) {
                // The stream is closed by the child or by process termination.
            }
            done = true;
        }

        public async void wait_done(int max_milliseconds = 2000) {
            int attempts = 0;
            int max_attempts = int.max(1, max_milliseconds / 5);
            while (!done && attempts < max_attempts) {
                Timeout.add(5, wait_done.callback);
                yield;
                attempts++;
            }
        }
    }
}
