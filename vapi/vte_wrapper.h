#pragma once
#include <gtk/gtk.h>
#include <pango/pango.h>
#include <unistd.h>
#include <termios.h>

G_BEGIN_DECLS

typedef enum {
  VTE_PTY_DEFAULT = 0,
  VTE_PTY_NO_LASTLOG = 1 << 0,
  VTE_PTY_NO_UTMP = 1 << 1,
  VTE_PTY_NO_WTMP = 1 << 2,
  VTE_PTY_NO_HELPER = 1 << 3,
  VTE_PTY_NO_FALLBACK = 1 << 4,
  VTE_PTY_DUPLICATE_FD = 1 << 5
} VtePtyFlags;

typedef struct _VteTerminal VteTerminal;
typedef struct _VtePty VtePty;

GType vte_terminal_get_type(void);
GtkWidget *vte_terminal_new(void);

void vte_terminal_spawn_async(
    VteTerminal *terminal,
    VtePtyFlags pty_flags,
    const char *working_directory,
    char **argv,
    char **envv,
    GSpawnFlags spawn_flags,
    GSpawnChildSetupFunc child_setup,
    gpointer child_setup_data,
    GDestroyNotify child_setup_data_destroy,
    int timeout,
    GCancellable *cancellable,
    GAsyncReadyCallback callback,
    gpointer user_data
);

static inline void vcmd_vte_terminal_spawn(
    VteTerminal *terminal,
    VtePtyFlags pty_flags,
    const char *working_directory,
    char **argv,
    char **envv,
    GSpawnFlags spawn_flags,
    int timeout
) {
    vte_terminal_spawn_async(
        terminal,
        pty_flags,
        working_directory,
        argv,
        envv,
        spawn_flags,
        NULL,
        NULL,
        NULL,
        timeout,
        NULL,
        NULL,
        NULL
    );
}

VtePty *vte_terminal_get_pty(VteTerminal *terminal);
int vte_pty_get_fd(VtePty *pty);

static inline int vcmd_vte_terminal_get_pty_fd(VteTerminal *terminal) {
    VtePty *pty = vte_terminal_get_pty(terminal);
    if (!pty) return -1;
    return vte_pty_get_fd(pty);
}

static inline int vcmd_vte_terminal_get_foreground_pgrp(VteTerminal *terminal) {
    int fd = vcmd_vte_terminal_get_pty_fd(terminal);
    if (fd < 0) return -1;
    return (int)tcgetpgrp(fd);
}

void vte_terminal_feed_child(VteTerminal *terminal, const char *text, gssize length);
void vte_terminal_reset(VteTerminal *terminal, gboolean clear_tabstops, gboolean clear_history);
void vte_terminal_copy_clipboard(VteTerminal *terminal);
void vte_terminal_paste_clipboard(VteTerminal *terminal);
void vte_terminal_set_font(VteTerminal *terminal, const PangoFontDescription *font_desc);
void vte_terminal_set_colors(VteTerminal *terminal, const GdkRGBA *foreground, const GdkRGBA *background, const GdkRGBA *palette, gsize palette_size);
void vte_terminal_set_scrollback_lines(VteTerminal *terminal, glong lines);
void vte_terminal_set_audible_bell(VteTerminal *terminal, gboolean is_audible);

G_END_DECLS


