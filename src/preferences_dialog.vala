namespace VCommander {

    public class PreferencesDialog : Object {
        public static void show(Gtk.Window parent, MainWindow main_win) {
            var config = ConfigManager.get_instance();

            var dialog = new Adw.PreferencesWindow();
            dialog.title = "Preferences";
            dialog.set_transient_for(parent);
            dialog.set_modal(true);
            dialog.set_default_size(600, 480);
            dialog.set_resizable(true);

            var page = new Adw.PreferencesPage();

            // Panels & Interface Group
            var panel_group = new Adw.PreferencesGroup();
            panel_group.title = "Panels &amp; Interface";
            panel_group.description = "Options for file panels and navigation toolbar";

            var toolbar_row = new Adw.SwitchRow();
            toolbar_row.title = "Show path toolbar under tabs";
            toolbar_row.subtitle = "Display path input bar with navigation and view toggle buttons in each panel";
            toolbar_row.active = config.show_path_toolbar;

            toolbar_row.notify["active"].connect(() => {
                config.show_path_toolbar = toolbar_row.active;
                config.save();
                main_win.apply_preferences();
            });

            panel_group.add(toolbar_row);
            page.add(panel_group);

            dialog.add(page);
            dialog.present();
        }
    }
}
