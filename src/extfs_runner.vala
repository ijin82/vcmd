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
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
            Subprocess proc = launcher.spawnv(argv);

            ulong cancel_handler_id = 0;
            if (cancellable != null) {
                cancel_handler_id = cancellable.connect(() => {
                    proc.force_exit();
                });
            }

            Error? proc_error = null;
            string? stderr_text = null;
            try {
                yield proc.communicate_utf8_async(null, cancellable, null, out stderr_text);
            } catch (Error e) {
                proc_error = e;
            } finally {
                if (cancel_handler_id != 0 && cancellable != null) {
                    cancellable.disconnect(cancel_handler_id);
                }
            }

            if (proc_error != null) {
                proc.force_exit();
                if (proc_error.matches(IOError.quark(), IOError.CANCELLED)) {
                    throw proc_error;
                }
                throw new IOError.FAILED(@"ExtFS helper failed: $(proc_error.message)");
            }

            int exit_code = proc.get_if_exited() ? proc.get_exit_status() : -1;
            if (exit_code != 0) {
                string msg = (stderr_text != null) ? stderr_text.strip() : "";
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
