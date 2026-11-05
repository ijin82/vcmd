.SUFFIXES:

VALAC = valac
TARGET = vcmd

VALAFLAGS = \
	--vapidir=vapi \
	--pkg gtk4 \
	--pkg libadwaita-1 \
	--pkg vte-2.91-gtk4 \
	--pkg gio-2.0 \
	--pkg gio-unix-2.0 \
	--pkg gdk-pixbuf-2.0 \
	--pkg posix \
	--target-glib=2.70 \
	-X -lm \
	-g

SOURCES = \
	src/config_manager.vala \
	src/key_utils.vala \
	src/app_logger.vala \
	src/thumbnail_service.vala \
	src/file_item.vala \
	src/volume_service.vala \
	src/drives_dialog.vala \
	src/file_panel_page.vala \
	src/file_panel.vala \
	src/file_operation_service.vala \
	src/device_detector.vala \
	src/drive_queue_manager.vala \
	src/operation_progress_dialog.vala \
	src/operations_popover.vala \
	src/shortcuts_dialog.vala \
	src/preferences_dialog.vala \
	src/bookmarks_dialog.vala \
	src/open_with_dialog.vala \
	src/file_search.vala \
	src/search_dialog.vala \
	src/remote_mount.vala \
	src/connect_dialog.vala \
	src/filesystem_repair_dialog.vala \
	src/wallpaper_service.vala \
	src/extfs_runner.vala \
	src/archive_registry.vala \
	src/archive_tree.vala \
	src/archive_password_dialog.vala \
	src/archive_pack_dialog.vala \
	src/archive_operation_service.vala \
	src/window.vala \
	src/application.vala \
	src/main.vala

all: build

build: $(TARGET)

$(TARGET): $(SOURCES)
	$(VALAC) $(VALAFLAGS) -o $(TARGET) $(SOURCES)

run: build
	./$(TARGET)

install:
	./install.sh install

install-lite:
	./install.sh lite

uninstall:
	./install.sh uninstall

package:
	./package-release.sh

release: package

clean:
	rm -f $(TARGET) src/*.c src/*.vala.c

.PHONY: all build run install install-lite uninstall clean package release
