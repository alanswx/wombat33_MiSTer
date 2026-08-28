# RTL-simulation payloads: the shared bench mains built for a bare
# 68040 core in a flat-RAM testbench (tb_corpus.v + AP68040 rtl).
# Same platform trio as the Amiga port minus the OS: external
# framebuffer, external (RAM memcpy) writer, raw-CPUSHA cache idiom
# (AMIGA_BENCH really means "bare-metal 040, no Mac ROM").
#
# Narrow the corpus for smoke runs:
#   make payloads CDEFS="-DLAST_TEST_INDEX=9"

VIDEO_VARIANT := mdc824

include ../common/make/common.mk

BUILD := build
SB    := ../supervisor_bench
COMMON_RUNTIME := $(COMMON)/runtime
COMMON_DISPLAY := $(COMMON)/display

SCFLAGS := $(CFLAGS) -DDISPLAY_FB_EXTERN -DJW_BACKEND_EXTERN -DAMIGA_BENCH

all: payloads
payloads: $(BUILD)/payload_cpu_sim.bin
.PHONY: all payloads clean

$(BUILD):
	mkdir -p $@

$(BUILD)/payload_entry_sim.o: payload_entry_sim.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<
$(BUILD)/jsonl_sim.o: jsonl_sim.c | $(BUILD)
	$(CC) $(SCFLAGS) -c -o $@ $<
$(BUILD)/eject_stub.o: ../amiga/eject_amiga.c | $(BUILD)
	$(CC) $(SCFLAGS) -c -o $@ $<
$(BUILD)/jsonl_writer.o: $(COMMON_RUNTIME)/jsonl_writer.c | $(BUILD)
	$(CC) $(SCFLAGS) -c -o $@ $<
$(BUILD)/freestanding.o: $(COMMON_RUNTIME)/freestanding.c | $(BUILD)
	$(CC) $(SCFLAGS) -c -o $@ $<
$(BUILD)/font_ascii.o: $(COMMON_DISPLAY)/display_1bpp.c | $(BUILD)
	$(CC) $(SCFLAGS) -c -o $@ $<
$(BUILD)/recovery.o: $(COMMON_RUNTIME)/recovery.s | $(BUILD)
	$(AS) $(ASFLAGS) --defsym NO_SCRNBASE_DOT=1 -o $@ $<
$(BUILD)/bench_main.o: $(SB)/bench_main.c ../../gen/cpu_tests.h | $(BUILD)
	$(CC) $(SCFLAGS) -I$(SB) -c -o $@ $<

SIM_OBJS := $(BUILD)/payload_entry_sim.o \
            $(BUILD)/jsonl_sim.o \
            $(BUILD)/eject_stub.o \
            $(BUILD)/jsonl_writer.o \
            $(BUILD)/freestanding.o \
            $(BUILD)/font_ascii.o \
            $(BUILD)/recovery.o \
            $(BUILD)/bench_main.o

$(BUILD)/payload_cpu_sim.elf: $(SIM_OBJS) $(PAYLOAD_LD)
	$(LD) $(LDFLAGS) -T $(PAYLOAD_LD) -o $@ $(SIM_OBJS)
$(BUILD)/payload%.bin: $(BUILD)/payload%.elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(BUILD)
