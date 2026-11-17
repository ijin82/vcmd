namespace VCommander.Tests {

    public class ConfigLoggerTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("config.atomic_save", "Save config atomically with mode 0600 and no temp leftovers", (ctx) => {
                run_atomic_save(ctx);
            });
            registry.add("config.version_precedence", "Installed version data wins over a local VERSION file", (ctx) => {
                run_version_precedence(ctx);
            });
            registry.add("logger.append_order", "Logger appends chronologically with mode 0600", (ctx) => {
                run_logger_append(ctx);
            });
        }

        private static void run_atomic_save(TestContext ctx) {
            try {
                var config = ConfigManager.get_instance();
                config.window_width = 1234;
                config.save();
                string config_path = Path.build_filename(Environment.get_user_config_dir(), "vcmd", "config");
                if (!ctx.expect(TestFs.exists(config_path), "config file created")) return;
                if (!ctx.expect(TestFs.mode(config_path) == 0600, @"config mode 0600, got $(TestFs.mode(config_path).to_string())")) return;
                string content = TestFs.read_text(config_path);
                if (!ctx.expect(content.contains("Width=1234"), "config contains saved width")) return;
                string dir = Path.get_dirname(config_path);
                var enumerator = File.new_for_path(dir).enumerate_children(
                    "standard::name",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    null
                );
                FileInfo? info = null;
                while ((info = enumerator.next_file(null)) != null) {
                    if (info.get_name().contains(".tmp.")) {
                        ctx.fail(@"temporary config file left behind: $(info.get_name())");
                        return;
                    }
                }
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ctx.finish();
            }
        }

        private static void run_version_precedence(TestContext ctx) {
            try {
                string data_dir = Path.build_filename(Environment.get_user_data_dir(), "vcmd");
                DirUtils.create_with_parents(data_dir, 0755);
                TestFs.write_text(Path.build_filename(data_dir, "VERSION"), "vTEST\n");
                string version = ConfigManager.get_version(true);
                if (!ctx.expect(version == "vTEST", @"expected vTEST, got $version")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ctx.finish();
            }
        }

        private static void run_logger_append(TestContext ctx) {
            try {
                AppLogger.init();
                AppLogger.info("Test", "first");
                AppLogger.info("Test", "second");
                string log_path = AppLogger.get_log_file_path();
                if (!ctx.expect(TestFs.exists(log_path), "log file created")) return;
                if (!ctx.expect(TestFs.mode(log_path) == 0600, @"log mode 0600, got $(TestFs.mode(log_path).to_string())")) return;
                string content = TestFs.read_text(log_path);
                string[] lines = content.strip().split("\n");
                if (!ctx.expect(lines.length >= 3, "log contains startup and test entries")) return;
                string first_ts = "";
                string last_ts = "";
                foreach (var line in lines) {
                    if (line.has_prefix("[") && line.length >= 21) {
                        if (first_ts.length == 0) first_ts = line.substring(0, 21);
                        last_ts = line.substring(0, 21);
                    }
                }
                if (!ctx.expect(first_ts.length > 0 && last_ts.length > 0, "timestamped log lines present")) return;
                if (!ctx.expect(first_ts <= last_ts, "log is chronological")) return;
                if (!ctx.expect(content.contains("[Test] first"), "first entry appended")) return;
                if (!ctx.expect(content.contains("[Test] second"), "second entry appended")) return;
            } catch (Error e) {
                ctx.fail(e.message);
            } finally {
                ctx.finish();
            }
        }
    }
}
