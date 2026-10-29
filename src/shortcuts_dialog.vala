namespace VCommander {

    public class ShortcutsDialog : Object {
        public static void show(Gtk.Window parent) {
            var dialog = new Adw.AlertDialog("Vala Commander", "Keyboard Shortcuts & Controls");
            dialog.add_response("close", "Close");
            dialog.set_default_response("close");
            dialog.set_close_response("close");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 8;
            box.margin_end = 8;

            // 1. Navigation & Panes
            var nav_group = new Adw.PreferencesGroup();
            nav_group.title = "Navigation & Panes";
            add_shortcut_row(nav_group, "Switch Active Pane", "Tab");
            add_shortcut_row(nav_group, "Tag / Untag File or Folder", "Insert / Right Click");
            add_shortcut_row(nav_group, "Clear All Tags / Selection", "Double Escape");
            add_shortcut_row(nav_group, "Select by Mask", "+ (Keypad) / Shift + +");
            add_shortcut_row(nav_group, "Enter Folder / Open File", "Enter / Double Click");
            add_shortcut_row(nav_group, "Go to Parent Directory", "Backspace / Alt + Up");
            add_shortcut_row(nav_group, "Focus Path Entry", "Ctrl + L");
            add_shortcut_row(nav_group, "Cycle View (Brief / Detailed / Super)", "Alt + T");
            add_shortcut_row(nav_group, "Toggle Hidden Files", "Ctrl + H");
            add_shortcut_row(nav_group, "Jump to Top / Beginning", "Left Arrow");
            add_shortcut_row(nav_group, "Jump to End / Last Item", "Right Arrow");
            add_shortcut_row(nav_group, "Calculate Directory / File Size", "Ctrl + Space");
            add_shortcut_row(nav_group, "Quick Filter (Substring)", "Ctrl + S");
            add_shortcut_row(nav_group, "Increase Brief Column Width", "Ctrl + +");
            add_shortcut_row(nav_group, "Decrease Brief Column Width", "Ctrl + -");
            add_shortcut_row(nav_group, "Sync Other Panel Directory", "Esc > i / Alt + i");
            box.append(nav_group);

            // 2. Terminal Command Line
            var cmd_group = new Adw.PreferencesGroup();
            cmd_group.title = "Terminal Command Line";
            add_shortcut_row(cmd_group, "Start Typing Command", "Type letters / digits");
            add_shortcut_row(cmd_group, "Insert Selected File Name", "Ctrl + Enter");
            add_shortcut_row(cmd_group, "Execute in Active Directory", "Enter (in command bar)");
            add_shortcut_row(cmd_group, "Fast Directory Navigation", "cd <dir> (e.g. cd /, cd ~)");
            add_shortcut_row(cmd_group, "Command History", "↑ / ↓");
            add_shortcut_row(cmd_group, "Cancel & Focus File List", "Escape");
            box.append(cmd_group);

            // 3. Tab Management
            var tab_group = new Adw.PreferencesGroup();
            tab_group.title = "Tab Management";
            add_shortcut_row(tab_group, "New Tab", "Ctrl + T");
            add_shortcut_row(tab_group, "Rename Current Tab (max 15 chars)", "Ctrl + Shift + T");
            add_shortcut_row(tab_group, "Close Current Tab", "Ctrl + W");
            add_shortcut_row(tab_group, "Previous Tab", "Ctrl + Page Up / Ctrl + Shift + Tab");
            add_shortcut_row(tab_group, "Next Tab", "Ctrl + Page Down / Ctrl + Tab");
            box.append(tab_group);

            // 4. Directory Bookmarks (Hotlist)
            var bm_group = new Adw.PreferencesGroup();
            bm_group.title = "Directory Bookmarks (Ctrl + \\)";
            add_shortcut_row(bm_group, "Open Bookmarks Dialog", "Ctrl + \\");
            add_shortcut_row(bm_group, "Add Current Directory", "Ctrl + A");
            add_shortcut_row(bm_group, "Navigate to Selected Bookmark", "Enter / Double Click");
            add_shortcut_row(bm_group, "Edit Bookmark Name", "E");
            add_shortcut_row(bm_group, "Move Bookmark Up", "Ctrl + Up");
            add_shortcut_row(bm_group, "Move Bookmark Down", "Ctrl + Down");
            add_shortcut_row(bm_group, "Delete Selected Bookmark", "Delete");
            box.append(bm_group);

            // 5. General & Function Keys (with stage indicators)
            var gen_group = new Adw.PreferencesGroup();
            gen_group.title = "General & Function Keys";
            add_shortcut_row(gen_group, "Keyboard Shortcuts", "F1");
            add_shortcut_row(gen_group, "Preferences", "Ctrl + ,");
            add_shortcut_row(gen_group, "Toggle Window Header Bar", "Ctrl + Shift + H");
            add_shortcut_row(gen_group, "View File", "F3");
            add_shortcut_row(gen_group, "Edit File", "F4");
            add_shortcut_row(gen_group, "Copy Files", "F5");
            add_shortcut_row(gen_group, "Move Files", "F6");
            add_shortcut_row(gen_group, "Rename File / Folder", "Shift + F6");
            add_shortcut_row(gen_group, "Create Folder", "F7");
            add_shortcut_row(gen_group, "Delete (Trash)", "Delete / F8");
            add_shortcut_row(gen_group, "Permanent Delete", "Shift + Delete / Shift + F8");
            add_shortcut_row(gen_group, "Quit Application", "F10 / Ctrl + Q");
            add_shortcut_row(gen_group, "Directory Bookmarks", "Ctrl + \\");
            add_shortcut_row(gen_group, "Search Files (Stage 6)", "Alt + F7");
            box.append(gen_group);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.propagate_natural_height = true;
            scrolled.max_content_height = 540;
            scrolled.min_content_width = 640;
            scrolled.width_request = 640;
            scrolled.set_child(box);

            dialog.set_extra_child(scrolled);
            dialog.present(parent);
        }

        private static void add_shortcut_row(Adw.PreferencesGroup group, string title, string shortcut) {
            var row = new Adw.ActionRow();
            row.title = Markup.escape_text(title);
            var badge = new Gtk.Label("<tt><b>%s</b></tt>".printf(Markup.escape_text(shortcut)));
            badge.use_markup = true;
            badge.add_css_class("dim-label");
            row.add_suffix(badge);
            group.add(row);
        }
    }
}
