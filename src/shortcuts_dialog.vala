namespace VCommander {

    public class ShortcutsDialog : Object {
        private static Adw.ShortcutsDialog? active_dialog = null;

        public static void show(Gtk.Window parent) {
            if (active_dialog != null) {
                active_dialog.present(parent);
                return;
            }

            var dialog = new Adw.ShortcutsDialog();
            active_dialog = dialog;

            dialog.closed.connect(() => {
                active_dialog = null;
            });

            // 1. Function Keys (F1..F10)
            var fn_section = new Adw.ShortcutsSection("Function Keys (F1..F10)");
            add_item(fn_section, "Help & Shortcuts", "F1");
            add_item(fn_section, "View File", "F3");
            add_item(fn_section, "Edit File", "F4");
            add_item(fn_section, "Copy Selected File(s)", "F5");
            add_item(fn_section, "Move Selected File(s)", "F6");
            add_item(fn_section, "Rename Item In-Place", "<Shift>F6");
            add_item(fn_section, "Create New Directory", "F7");
            add_item(fn_section, "Move to Trash", "F8", "or Delete");
            add_item(fn_section, "Permanently Delete", "<Shift>F8", "or Shift+Delete");
            add_item(fn_section, "Quit Vala Commander", "F10", "or Ctrl+Q");
            add_item(fn_section, "Search Files & Content", "<Alt>F7", "Stage 6");
            dialog.add(fn_section);

            // 2. Navigation & Panels
            var nav_section = new Adw.ShortcutsSection("Navigation & Panes");
            add_item(nav_section, "Switch Active Pane", "Tab");
            add_item(nav_section, "Enter Directory / Open File", "Return", "or Double Click");
            add_item(nav_section, "Open With...", "<Control>o", "Choose custom application");
            add_item(nav_section, "Go to Parent Directory", "BackSpace", "or Alt+Up");
            add_item(nav_section, "Jump to First Item", "Home", "or Left Arrow");
            add_item(nav_section, "Jump to Last Item", "End", "or Right Arrow");
            add_item(nav_section, "Focus Path Entry", "<Control>l");
            add_item(nav_section, "Sync Opposite Panel Directory", "<Alt>i", "or Esc then i");
            add_item(nav_section, "Quick Filter by Substring", "<Control>s");
            add_item(nav_section, "Calculate Folder / File Size", "<Control>space", "or Space on folder");
            add_item(nav_section, "Cycle View Mode", "<Alt>t", "Brief -> Detailed -> Super Detailed");
            add_item(nav_section, "Toggle Hidden Files", "<Control>h");
            add_item(nav_section, "Increase Brief Column Width", "<Control>plus");
            add_item(nav_section, "Decrease Brief Column Width", "<Control>minus");
            dialog.add(nav_section);

            // 3. Selection & Tagging
            var sel_section = new Adw.ShortcutsSection("Selection & Tagging");
            add_item(sel_section, "Tag / Untag Current Item", "Insert", "or Right Click");
            add_item(sel_section, "Select by Mask (Wildcards)", "plus", "Keypad + or Shift + +");
            add_item(sel_section, "Clear All Tags / Selection", "Escape", "Press Escape twice quickly");
            dialog.add(sel_section);

            // 4. Tabs Management
            var tab_section = new Adw.ShortcutsSection("Tab Management");
            add_item(tab_section, "New Tab", "<Control>t");
            add_item(tab_section, "Rename Current Tab", "<Control><Shift>t", "Up to 15 characters");
            add_item(tab_section, "Close Current Tab", "<Control>w");
            add_item(tab_section, "Previous Tab", "<Control>Page_Up", "or Ctrl+Shift+Tab");
            add_item(tab_section, "Next Tab", "<Control>Page_Down", "or Ctrl+Tab");
            dialog.add(tab_section);

            // 5. Directory Bookmarks (Hotlist)
            var bm_section = new Adw.ShortcutsSection("Directory Bookmarks");
            add_item(bm_section, "Open Bookmarks Dialog", "<Control>backslash");
            add_item(bm_section, "Add Current Directory", "<Control>a", "Inside bookmarks dialog");
            add_item(bm_section, "Open Selected Bookmark", "Return", "Inside bookmarks dialog");
            add_item(bm_section, "Edit Bookmark Name", "e", "Inside bookmarks dialog");
            add_item(bm_section, "Move Bookmark Up", "<Control>Up", "Inside bookmarks dialog");
            add_item(bm_section, "Move Bookmark Down", "<Control>Down", "Inside bookmarks dialog");
            add_item(bm_section, "Delete Selected Bookmark", "Delete", "Inside bookmarks dialog");
            dialog.add(bm_section);

            // 6. Terminal Command Bar
            var cmd_section = new Adw.ShortcutsSection("Terminal Command Line");
            add_item(cmd_section, "Start Typing Command", "Return", "Type letters or digits anywhere in list");
            add_item(cmd_section, "Insert Selected File Name", "<Control>Return");
            add_item(cmd_section, "Execute Command in Active Dir", "Return", "When command entry is focused");
            add_item(cmd_section, "Fast Directory Navigation", "Return", "cd <dir> (e.g. cd /, cd ~)");
            add_item(cmd_section, "Command History", "Up", "Up / Down arrow keys");
            add_item(cmd_section, "Cancel & Focus File List", "Escape");
            dialog.add(cmd_section);

            // 7. Application & Settings
            var app_section = new Adw.ShortcutsSection("Application & Settings");
            add_item(app_section, "Preferences Dialog", "<Control>comma");
            add_item(app_section, "Toggle Header Bar", "<Control><Shift>h");
            add_item(app_section, "Reset Splitter to 50/50", "Return", "Double click pane divider handle");
            add_item(app_section, "Quit Vala Commander", "<Control>q", "or F10");
            dialog.add(app_section);

            dialog.present(parent);
        }

        private static void add_item(Adw.ShortcutsSection section, string title, string accelerator, string? subtitle = null) {
            var item = new Adw.ShortcutsItem(title, accelerator);
            if (subtitle != null && subtitle.length > 0) {
                item.subtitle = subtitle;
            }
            section.add(item);
        }
    }
}
