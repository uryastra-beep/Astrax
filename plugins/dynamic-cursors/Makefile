PLUGIN_NAME=dynamic-cursors

# Hyprland 0.57 reworked the render and window APIs: src/ targets >= 0.57,
# src-hl056/ is the previous port for 0.56.x. Override with SRC=... if needed.
HL_VERSION := $(shell pkg-config --modversion hyprland 2>/dev/null)
SRC ?= $(shell [ -n "$(HL_VERSION)" ] && [ "$$(printf '%s\n0.57.0\n' "$(HL_VERSION)" | sort -V | head -n1)" != 0.57.0 ] && echo src-hl056 || echo src)

SOURCE_FILES := $(wildcard ./$(SRC)/*.cpp ./$(SRC)/*/*.cpp ./$(SRC)/*/*/*.cpp)
HEADER_FILES := $(wildcard ./$(SRC)/*.hpp ./$(SRC)/*/*.hpp ./$(SRC)/*/*/*.hpp)

OBJECT_FILES := $(patsubst ./$(SRC)/%.cpp, out/%.o, $(SOURCE_FILES))
CXXFLAGS := -MMD -MP -Wall -fPIC -std=c++26 -g \
	$(shell pkg-config --cflags hyprland pixman-1 libdrm | sed 's#-I\([^ ]*/hyprland\)\($$\| \)#-I\1 -I\1/src #g')

OUTPUT=out/$(PLUGIN_NAME).so

ifeq ($(CXX),g++)
    CXXFLAGS += --no-gnu-unique
endif

.PHONY: all clean load unload format

all: $(OUTPUT)

$(OUTPUT): $(OBJECT_FILES)
	$(CXX) -shared $^ $(LDFLAGS) -o $@

# Compile step (object file per .cpp)
out/%.o: ./$(SRC)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_CXXFLAGS) -c $< -o $@

clean:
	$(RM) $(OUTPUT) $(OBJECT_FILES)

format:
	clang-format -i $(HEADER_FILES) $(SOURCE_FILES)

load: all unload
	hyprctl plugin load ${PWD}/$(OUTPUT)

unload:
	hyprctl plugin unload ${PWD}/$(OUTPUT)
-include $(OBJECT_FILES:.o=.d)
