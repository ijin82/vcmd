namespace VCommander {

    public static int main(string[] args) {
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
