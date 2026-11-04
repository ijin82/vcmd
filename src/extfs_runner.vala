namespace VCommander {

    public class ExtFSRunner : Object {
        private static ExtFSRunner? instance = null;

        public static ExtFSRunner get_instance() {
            if (instance == null) {
                instance = new ExtFSRunner();
            }
            return instance;
        }

        public async Subprocess spawn_list(ExtFSHelperInfo helper, string archive_path, Cancellable? cancellable = null) throws Error {
            string[] argv = { helper.script_path, "list", archive_path };
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            return launcher.spawnv(argv);
        }

        public async void copyout(ExtFSHelperInfo helper, string archive_path, string stored_path, string dest_path, Cancellable? cancellable = null) throws Error {
            string[] argv = { helper.script_path, "copyout", archive_path, stored_path, dest_path };
            yield run_command_with_check(argv, cancellable);
        }

        public async void copyin(ExtFSHelperInfo helper, string archive_path, string stored_path, string src_path, Cancellable? cancellable = null) throws Error {
            string[] argv = { helper.script_path, "copyin", archive_path, stored_path, src_path };
            yield run_command_with_check(argv, cancellable);
        }

        public async void rm(ExtFSHelperInfo helper, string archive_path, string stored_path, Cancellable? cancellable = null) throws Error {
            string[] argv = { helper.script_path, "rm", archive_path, stored_path };
            yield run_command_with_check(argv, cancellable);
        }

        public async void mkdir(ExtFSHelperInfo helper, string archive_path, string dir_path, Cancellable? cancellable = null) throws Error {
            string[] argv = { helper.script_path, "mkdir", archive_path, dir_path };
            yield run_command_with_check(argv, cancellable);
        }

        public async void copyout_by_name(string helper_name, string archive_path, string stored_path, string dest_path, Cancellable? cancellable = null) throws Error {
            var helper = ArchiverRegistry.get_instance().find_extfs_helper(helper_name);
            if (helper == null) {
                throw new IOError.NOT_SUPPORTED(@"ExtFS helper '$helper_name' not found");
            }
            yield copyout(helper, archive_path, stored_path, dest_path, cancellable);
        }

        public async void copyin_by_name(string helper_name, string archive_path, string stored_path, string src_path, Cancellable? cancellable = null) throws Error {
            var helper = ArchiverRegistry.get_instance().find_extfs_helper(helper_name);
            if (helper == null) {
                throw new IOError.NOT_SUPPORTED(@"ExtFS helper '$helper_name' not found");
            }
            yield copyin(helper, archive_path, stored_path, src_path, cancellable);
        }

        public async void rm_by_name(string helper_name, string archive_path, string stored_path, Cancellable? cancellable = null) throws Error {
            var helper = ArchiverRegistry.get_instance().find_extfs_helper(helper_name);
            if (helper == null) {
                throw new IOError.NOT_SUPPORTED(@"ExtFS helper '$helper_name' not found");
            }
            yield rm(helper, archive_path, stored_path, cancellable);
        }

        public async void mkdir_by_name(string helper_name, string archive_path, string dir_path, Cancellable? cancellable = null) throws Error {
            var helper = ArchiverRegistry.get_instance().find_extfs_helper(helper_name);
            if (helper == null) {
                throw new IOError.NOT_SUPPORTED(@"ExtFS helper '$helper_name' not found");
            }
            yield mkdir(helper, archive_path, dir_path, cancellable);
        }

        private async void run_command_with_check(string[] argv, Cancellable? cancellable) throws Error {
            var launcher = new SubprocessLauncher(SubprocessFlags.STDERR_PIPE);
            Subprocess proc = launcher.spawnv(argv);

            var err_stream = new DataInputStream(proc.get_stderr_pipe());
            var err_sb = new StringBuilder();

            try {
                yield proc.wait_check_async(cancellable);
            } catch (Error e) {
                size_t len;
                string? err_line;
                try {
                    while ((err_line = yield err_stream.read_line_utf8_async(Priority.DEFAULT, null, out len)) != null) {
                        err_sb.append(err_line);
                        err_sb.append("\n");
                    }
                } catch (Error ignored) {}

                string msg = err_sb.str.strip();
                int exit_code = proc.get_if_exited() ? proc.get_exit_status() : -1;
                string helper_name = Path.get_basename(argv[0]);
                if (msg.length > 0) {
                    throw new IOError.FAILED(@"ExtFS helper '$helper_name' failed (exit code $exit_code): $msg");
                } else {
                    throw new IOError.FAILED(@"ExtFS helper '$helper_name' failed with exit code $exit_code");
                }
            }
        }
    }
}
