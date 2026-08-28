// wombat33 — Verilator simulation main
//
// Same framework as the other cores' verilator setups (ImGui + SDL2,
// sim_video/sim_clock/sim_input helpers, FST tracing): a control window
// with run/pause/step, the core's option bits, and the emulated screen.
// Today it drives the MiSTer template pattern core in sim.v; the AP68040
// machine drops into the same shell as bring-up proceeds.

#include <verilated.h>
#include "Vemu.h"
#include "Vemu__Syms.h"

#include "imgui.h"
#include <stdio.h>
#include <SDL.h>
#include <SDL_opengl.h>

#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)
#if VERILATOR_MAJOR_VERSION >= 5
#define VERTOPINTERN top->rootp
#else
#define VERTOPINTERN top
#endif

#include "sim_console.h"
#include "sim_video.h"
#include "sim_input.h"
#include "sim_clock.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "sim/stb_image_write.h"

#include <string>
#include <sstream>
#include <vector>
#include <algorithm>

// Simulation control
// ------------------
int  initialReset = 48;
bool run_enable = 1;
int  batchSize = 150000;
bool single_step = 0;
bool multi_step = 0;
int  multi_step_amount = 1024;

// Core options (mirrors the CONF_STR options in wombat33.sv)
int opt_tvmode = 0;      // 0 NTSC, 1 PAL
int opt_noise = 0;       // 0 white, 1 red, 2 green, 3 blue

// Headless / scripted runs
bool headless = false;
bool screenshot_mode = false;
std::vector<int> screenshot_frames;
int  stop_at_frame = -1;

// Verilog module
// --------------
Vemu* top = NULL;
vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

SimClock clk_sys(1);

DebugConsole console;
const char* windowTitle = "wombat33 sim";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_Video = "VGA output";

// Video: template pattern is 640x480-ish; the window autosizes to the
// measured extents anyway.
SimVideo video(800, 600, 0);
float vga_scale = 1.0f;
SimInput input(12, console);

static void save_screenshot(int frame) {
	char filename[64];
	snprintf(filename, sizeof(filename), "screenshot_f%d.png", frame);
	stbi_write_png(filename, output_width, output_height, 4, output_ptr,
	               output_width * 4);
	printf("Saved %s (%dx%d)\n", filename, output_width, output_height);
}

int verilate() {
	if (!Verilated::gotFinish()) {
		if (main_time < (vluint64_t)initialReset) VERTOPINTERN->reset = 1;
		if (main_time == (vluint64_t)initialReset) VERTOPINTERN->reset = 0;

		clk_sys.Tick();
		VERTOPINTERN->clk_sys = clk_sys.clk;
		VERTOPINTERN->sim_status =
			((opt_tvmode & 1) << 2) | ((opt_noise & 3) << 3);

		if (clk_sys.clk != clk_sys.old) {
			if (clk_sys.clk) input.BeforeEval();
			top->eval();
		}

		if (clk_sys.IsRising() && VERTOPINTERN->CE_PIXEL) {
			uint32_t colour = 0xFF000000 |
				(VERTOPINTERN->VGA_B << 16) |
				(VERTOPINTERN->VGA_G << 8) |
				 VERTOPINTERN->VGA_R;
			video.Clock(VERTOPINTERN->VGA_HB, VERTOPINTERN->VGA_VB,
			            VERTOPINTERN->VGA_HS, VERTOPINTERN->VGA_VS, colour);
		}

		main_time++;
		return 1;
	}
	return 0;
}

int main(int argc, char** argv, char** env) {
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--no-gui")) {
			headless = true;
		} else if (!strcmp(argv[i], "--screenshot") && i + 1 < argc) {
			screenshot_mode = true;
			std::stringstream ss(argv[++i]);
			std::string n;
			while (std::getline(ss, n, ',')) screenshot_frames.push_back(std::stoi(n));
		} else if (!strcmp(argv[i], "--stop-at-frame") && i + 1 < argc) {
			stop_at_frame = std::stoi(argv[++i]);
		} else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
			printf("wombat33 sim: [--headless] [--screenshot F1,F2,..] [--stop-at-frame N]\n");
			return 0;
		}
	}

	top = new Vemu();
	Verilated::commandArgs(argc, argv);
	Verilated::traceEverOn(true);

	VERTOPINTERN->clk_sys = 0;
	VERTOPINTERN->reset = 1;
	VERTOPINTERN->ps2_key = 0;
	VERTOPINTERN->ps2_mouse = 0;
	VERTOPINTERN->ioctl_download = 0;
	VERTOPINTERN->ioctl_wr = 0;
	VERTOPINTERN->ioctl_addr = 0;
	VERTOPINTERN->ioctl_dout = 0;
	VERTOPINTERN->ioctl_index = 0;
	top->eval();

	input.Initialise();
	if (!headless) {
		if (video.Initialise(windowTitle) == 1) return 1;
	} else {
		// video.Initialise allocates the pixel buffer; headless runs skip
		// the SDL window but still render into the buffer for screenshots.
		// The sim_video globals default to 512x512 until Initialise: size
		// them from the SimVideo instance so frames are not clipped.
		extern unsigned int output_size;
		output_width = video.output_width;
		output_height = video.output_height;
		output_size = output_width * output_height * 4;
		output_ptr = (uint32_t*)calloc(1, output_size);
	}

	bool done = false;
	while (!done) {
		if (!headless) {
			SDL_Event event;
			while (SDL_PollEvent(&event)) {
				ImGui_ImplSDL2_ProcessEvent(&event);
				if (event.type == SDL_QUIT) done = true;
			}

			video.StartFrame();
			input.Read();

			ImGui::NewFrame();
			ImGui::Begin(windowTitle_Control);
			ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
			ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 250), ImGuiCond_Once);
			if (ImGui::Button("Reset simulation")) { main_time = 0; }
			ImGui::SameLine();
			if (ImGui::Button("Reset core")) {
				VERTOPINTERN->reset = 1;
				for (int i = 0; i < 8; i++) verilate();
				VERTOPINTERN->reset = 0;
			}
			ImGui::Checkbox("RUN", &run_enable);
			ImGui::SliderInt("Batch size", &batchSize, 1000, 1000000);
			if (single_step) single_step = 0;
			if (ImGui::Button("Single step")) single_step = 1;
			ImGui::SameLine();
			if (multi_step) multi_step = 0;
			if (ImGui::Button("Multi step")) multi_step = 1;
			ImGui::SameLine();
			ImGui::SliderInt("Steps", &multi_step_amount, 8, 1024);

			ImGui::Separator();
			ImGui::Text("Core options (CONF_STR mirror)");
			ImGui::Combo("TV mode", &opt_tvmode, "NTSC\0PAL\0");
			ImGui::Combo("Noise", &opt_noise, "White\0Red\0Green\0Blue\0");

			ImGui::Separator();
			ImGui::Text("Frame %06d  %.1f fps  %dx%d", video.count_frame,
			            video.stats_fps, video.stats_xMax - video.stats_xMin + 1,
			            video.stats_yMax - video.stats_yMin + 1);
			ImGui::End();

			ImGui::Begin(windowTitle_Video);
			ImGui::SetWindowPos(windowTitle_Video, ImVec2(0, 260), ImGuiCond_Once);
			ImGui::SetWindowSize(windowTitle_Video,
				ImVec2(video.output_width * vga_scale + 24,
				       video.output_height * vga_scale + 46), ImGuiCond_Once);
			ImGui::SliderFloat("Zoom", &vga_scale, 0.5, 4.0);
			ImGui::Image(video.texture_id,
				ImVec2(video.output_width * vga_scale,
				       video.output_height * vga_scale));
			ImGui::End();

			video.UpdateTexture();
		}

		if (screenshot_mode) {
			auto it = std::find(screenshot_frames.begin(), screenshot_frames.end(),
			                    (int)video.count_frame);
			if (it != screenshot_frames.end()) {
				save_screenshot(video.count_frame);
				screenshot_frames.erase(it);
			}
		}
		if (stop_at_frame >= 0 && (int)video.count_frame >= stop_at_frame) {
			printf("Reached frame %d, exiting\n", stop_at_frame);
			break;
		}

		if (run_enable)
			for (int step = 0; step < batchSize; step++) verilate();
		else {
			if (single_step) verilate();
			if (multi_step)
				for (int step = 0; step < multi_step_amount; step++) verilate();
		}

		if (headless && Verilated::gotFinish()) done = true;
	}

	if (!headless) { video.CleanUp(); input.CleanUp(); }
	top->final();
	delete top;
	return 0;
}
