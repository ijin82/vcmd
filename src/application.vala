namespace VCommander {

    public class Application : Adw.Application {
        private MainWindow? main_window = null;

        public Application() {
            Object(
                application_id: "org.vcmd.ValaCommander",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void startup() {
            base.startup();

            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => {
                quit();
            });
            add_action(quit_action);
            set_accels_for_action("app.quit", new string[] { "<Control>q", "<Control>Q" });
        }

        protected override void activate() {
            if (main_window == null) {
                main_window = new MainWindow(this);
            }
            main_window.present();
        }
    }
}
