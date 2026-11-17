using VCommander.Tests;

namespace VCommander.Tests {

    private enum TestResult {
        PASS,
        FAIL,
        SKIP
    }

    public static int main(string[] args) {
        var registry = new TestRegistry();
        PathUtilsTests.register(registry);
        FileOperationsTests.register(registry);
        ArchiveTreeTests.register(registry);
        RegistryTests.register(registry);
        ProcessUtilsTests.register(registry);
        ConfigLoggerTests.register(registry);
        RemoteHelpersTests.register(registry);
        ScriptsTests.register(registry);
        TempCleanupTests.register(registry);

        bool list_only = false;
        string? run_name = null;
        for (int i = 1; i < args.length; i++) {
            if (args[i] == "--list") {
                list_only = true;
            } else if (args[i] == "--run" && i + 1 < args.length) {
                run_name = args[i + 1];
                i++;
            }
        }

        if (list_only) {
            foreach (var tc in registry.get_cases()) {
                stdout.printf("%s|%s\n", tc.name, tc.description);
            }
            return 0;
        }

        if (run_name != null) {
            var tc = registry.find(run_name);
            if (tc == null) {
                stderr.printf("Unknown test: %s\n", run_name);
                return 2;
            }
            TestResult result = run_case(tc);
            return result == TestResult.FAIL ? 1 : 0;
        }

        stderr.printf("Use --list or --run <test>. Run ./tests/run_tests.sh for all tests.\n");
        return 2;
    }

    private static TestResult run_case(TestCase tc) {
        var ctx = new TestContext();
        bool timed_out = false;
        uint timeout_id = Timeout.add_seconds(30, () => {
            timed_out = true;
            ctx.fail(@"Test timed out after 30 seconds");
            ctx.finish();
            return Source.REMOVE;
        });

        tc.func(ctx);
        if (!ctx.done) {
            ctx.loop.run();
        }
        Source.remove(timeout_id);

        if (timed_out) {
            stdout.printf("FAIL  %s\n      %s\n", tc.name, ctx.failure ?? "timeout");
            return TestResult.FAIL;
        }
        if (ctx.skipped) {
            stdout.printf("SKIP  %s (%s)\n", tc.name, ctx.skip_reason ?? "skipped");
            return TestResult.SKIP;
        }
        if (ctx.failed) {
            stdout.printf("FAIL  %s\n      %s\n", tc.name, ctx.failure ?? "unknown failure");
            return TestResult.FAIL;
        }
        stdout.printf("PASS  %s\n", tc.name);
        return TestResult.PASS;
    }
}
