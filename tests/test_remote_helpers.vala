namespace VCommander.Tests {

    public class RemoteHelpersTests : Object {
        public static void register(TestRegistry registry) {
            registry.add("remote.build_uri", "Build SFTP-style URIs with port and path", (ctx) => {
                run_build_uri(ctx);
            });
            registry.add("remote.path_detection", "Detect remote versus local/archive paths", (ctx) => {
                run_path_detection(ctx);
            });
        }

        private static void run_build_uri(TestContext ctx) {
            try {
                string uri = RemoteMount.build_uri("ssh", "example.com", "2222", "user", "srv/data");
                if (!ctx.expect(uri == "ssh://user@example.com:2222/srv/data", @"unexpected URI: $uri")) return;
                string no_user = RemoteMount.build_uri("sftp", "example.com", "", "", "");
                if (!ctx.expect(no_user == "sftp://example.com/", @"unexpected URI: $no_user")) return;
            } finally {
                ctx.finish();
            }
        }

        private static void run_path_detection(TestContext ctx) {
            try {
                if (!ctx.expect(RemoteMount.is_remote_path("sftp://example.com/path"), "sftp URI is remote")) return;
                if (!ctx.expect(RemoteMount.is_remote_path("smb://server/share"), "smb URI is remote")) return;
                if (!ctx.expect(!RemoteMount.is_remote_path("/tmp/local"), "local path is not remote")) return;
                if (!ctx.expect(!RemoteMount.is_remote_path("archive:///tmp/a.zip/x"), "archive URI is not remote")) return;
            } finally {
                ctx.finish();
            }
        }
    }
}
