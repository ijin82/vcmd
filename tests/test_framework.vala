namespace VCommander.Tests {

    public delegate void TestFunc(TestContext ctx);

    public class TestCase : Object {
        public string name;
        public string description;
        public TestFunc func;

        public TestCase(string name, string description, TestFunc func) {
            this.name = name;
            this.description = description;
            this.func = func;
        }
    }

    public class TestContext : Object {
        public MainLoop loop;
        public bool done = false;
        public bool failed = false;
        public bool skipped = false;
        public string? failure = null;
        public string? skip_reason = null;

        public TestContext() {
            loop = new MainLoop();
        }

        public bool expect(bool condition, string description) {
            if (!condition) {
                fail(description);
                return false;
            }
            return true;
        }

        public void fail(string message) {
            if (!failed) {
                failed = true;
                failure = message;
            }
        }

        public void skip(string reason) {
            skipped = true;
            skip_reason = reason;
        }

        public void finish() {
            if (!done) {
                done = true;
                loop.quit();
            }
        }
    }

    public class TestRegistry : Object {
        private GenericArray<TestCase> cases;

        public TestRegistry() {
            cases = new GenericArray<TestCase>();
        }

        public void add(string name, string description, TestFunc func) {
            cases.add(new TestCase(name, description, func));
        }

        public TestCase? find(string name) {
            for (uint i = 0; i < cases.length; i++) {
                if (cases.get(i).name == name) {
                    return cases.get(i);
                }
            }
            return null;
        }

        public GenericArray<TestCase> get_cases() {
            return cases;
        }
    }

    public class TestFs : Object {
        public static string create_temp_root() throws Error {
            return DirUtils.make_tmp("vcmd-test-XXXXXX");
        }

        public static File file(string path) {
            return File.new_for_path(path);
        }

        public static void write_text(string path, string text) throws Error {
            var file = File.new_for_path(path);
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                parent.make_directory_with_parents(null);
            }
            file.replace_contents(text.data, null, false, FileCreateFlags.NONE, null, null);
        }

        public static string read_text(string path) throws Error {
            string contents;
            FileUtils.get_contents(path, out contents);
            return contents;
        }

        public static void remove_tree(string path) {
            var file = File.new_for_path(path);
            remove_tree_file(file);
        }

        private static void remove_tree_file(File file) {
            try {
                var info = file.query_info(
                    "standard::type",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    null
                );
                if (info.get_file_type() == FileType.DIRECTORY) {
                    var enumerator = file.enumerate_children(
                        "standard::name,standard::type",
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                        null
                    );
                    FileInfo? child_info = null;
                    while ((child_info = enumerator.next_file(null)) != null) {
                        remove_tree_file(file.get_child(child_info.get_name()));
                    }
                }
                file.delete(null);
            } catch (Error e) {
                // Best-effort cleanup only.
            }
        }

        public static uint32 mode(string path) throws Error {
            Posix.Stat st;
            if (Posix.lstat(path, out st) != 0) {
                throw new IOError.FAILED(@"Cannot stat: $path");
            }
            return (uint32) (st.st_mode & 07777);
        }

        public static bool exists(string path) {
            Posix.Stat st;
            return Posix.lstat(path, out st) == 0;
        }
    }
}
