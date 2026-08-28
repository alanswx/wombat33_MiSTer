# wombat33 — Verilator GUI simulation (same setup as the other cores'
# verilator directories: ImGui + SDL2, FST tracing, `make && ./obj_dir/Vemu`).
V = verilator

TOP = --top-module emu
RTL = ../rtl
V_INC = +incdir+$(RTL)

V_DEFINE = +define+SIMULATION=1 \
	-CFLAGS "-I../sim/imgui -I../sim/ -g" \
	--timescale-override 1ps/1ps -Wno-TIMESCALEMOD \
	-I$(RTL)
V_DEFINE += -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-IMPLICIT \
	-Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
	-Wno-UNSIGNED -Wno-CMPCONST -Wno-LATCH -Wno-UNDRIVEN -Wno-MISINDENT \
	-Wno-COMBDLY -Wno-INITIALDLY -Wno-SYNCASYNCNET -Wno-BLKLOOPINIT \
	-Wno-MULTIDRIVEN -Wno-GENUNNAMED
V_DEFINE += --trace-fst --timing

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Linux)
	LIBS += -lGL -ldl `sdl2-config --libs`
	CXXFLAGS += `sdl2-config --cflags` -Iimgui
	CFLAGS = $(CXXFLAGS)
endif

CFLAGS += -Iimgui
LDFLAGS = $(LIBS)
EXE = ./obj_dir/Vemu
V_OPT = --x-assign fast --x-initial fast --noassert

# Core RTL under simulation (the template pattern core today; the
# AP68040 machine's files join this list as bring-up proceeds — the CPU
# itself comes from ../rtl/ap68040/rtl).
V_SRC = \
	sim.v \
	$(RTL)/mycore.v \
	$(RTL)/cos.sv \
	sim_lfsr.v

C_SRC = \
	sim_main.cpp \
	sim/sim_console.cpp sim/sim_video.cpp sim/sim_input.cpp sim/sim_clock.cpp \
	sim/m68kdasm.c sim/m68k_dasm_stubs.cpp \
	sim/imgui/imgui_impl_sdl.cpp sim/imgui/imgui_impl_opengl2.cpp \
	sim/imgui/imgui_draw.cpp sim/imgui/imgui_widgets.cpp \
	sim/imgui/imgui_tables.cpp sim/imgui/imgui.cpp \
	sim/imgui/ImGuiFileDialog.cpp sim/imgui/implot.cpp sim/imgui/implot_items.cpp

VOUT = obj_dir/Vemu.cpp

all: $(EXE)

$(VOUT): $(V_SRC) $(C_SRC) Makefile
	$V -cc $(V_OPT) -LDFLAGS "$(LDFLAGS)" -exe --trace --Mdir ./obj_dir \
		$(V_DEFINE) $(V_INC) $(TOP) -CFLAGS $(CFLAGS) $(V_SRC) $(C_SRC)
	@touch $(VOUT)

$(EXE): $(VOUT)
	@# verilator's Vemu.mk has no dep tracking for our C sources: evict
	@# any object older than its source before the inner make.
	@for f in $(C_SRC); do o=obj_dir/$$(basename $${f%.*}).o; \
		[ -e $$o ] && [ $$f -nt $$o ] && rm -f $$o obj_dir/Vemu || true; done
	(cd obj_dir; make -f Vemu.mk)

clean:
	rm -rf obj_dir
