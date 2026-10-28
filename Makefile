.SUFFIXES:

VALAC = valac
TARGET = vcmd

VALAFLAGS = \
	--pkg gtk4 \
	--pkg libadwaita-1 \
	--pkg gio-2.0 \
	--pkg gio-unix-2.0 \
	--target-glib=2.70 \
	-g

SOURCES = \
	src/config_manager.vala \
	src/key_utils.vala \
	src/file_item.vala \
	src/file_panel_page.vala \
	src/file_panel.vala \
	src/shortcuts_dialog.vala \
	src/window.vala \
	src/application.vala \
	src/main.vala

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(VALAC) $(VALAFLAGS) -o $(TARGET) $(SOURCES)

run: all
	./$(TARGET)

clean:
	rm -f $(TARGET) src/*.c src/*.vala.c

.PHONY: all run clean
