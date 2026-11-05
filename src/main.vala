namespace VCommander {

    [CCode (cname = "mallopt", cheader = "malloc.h")]
    private extern static int mallopt(int param, int value);

    public static int main(string[] args) {
        // Optimize glibc memory allocator for low memory footprint and quick page release
        mallopt(-8, 2);             // M_ARENA_MAX = 2 (restrict multi-thread memory arenas)
        mallopt(-1, 128 * 1024);    // M_TRIM_THRESHOLD = 128KB (aggressively return heap memory to OS)
        mallopt(-3, 64 * 1024);     // M_MMAP_THRESHOLD = 64KB (allocate image buffers via direct mmap/munmap)

        if (args.length > 1) {
            string arg = args[1].strip();
            if (arg == "--version" || arg == "-v") {
                stdout.printf("Vala Commander %s\n", ConfigManager.get_version());
                return 0;
            }
        }
        var app = new Application();
        return app.run(args);
    }
}
