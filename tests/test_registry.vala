namespace VCommander.Tests {

    public class RegistryTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("registry.extensions", "Recognize common archive filename extensions", (ctx) => {
                run_extensions(ctx);
            });
            registry.add("registry.formats", "Find pack formats by extension", (ctx) => {
                run_formats(ctx);
            });
        }

        private static void run_extensions(TestContext ctx) {
            try {
                var registry = ArchiverRegistry.get_instance();
                if (!ctx.expect(registry.is_archive_filename("sample.tar.gz"), "tar.gz recognized")) return;
                if (!ctx.expect(registry.is_archive_filename("sample.zip"), "zip recognized")) return;
                if (!ctx.expect(registry.is_archive_filename("sample.7z"), "7z recognized")) return;
                if (!ctx.expect(!registry.is_archive_filename("sample.txt"), "text file not recognized")) return;
            } finally {
                ctx.finish();
            }
        }

        private static void run_formats(TestContext ctx) {
            try {
                var registry = ArchiverRegistry.get_instance();
                var zip = registry.find_format_by_extension(".zip");
                var tar_gz = registry.find_format_by_extension("tar.gz");
                if (!ctx.expect(zip != null, "zip format registered")) return;
                if (!ctx.expect(tar_gz != null, "tar.gz format registered")) return;
                if (!ctx.expect(zip.id == "zip", "zip format id")) return;
            } finally {
                ctx.finish();
            }
        }
    }
}
