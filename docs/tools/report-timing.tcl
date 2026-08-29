# report-timing.tcl — dump the worst timing paths from an EXISTING compile.
#
# The default compile flow's wombat33.sta.rpt carries only per-clock slack
# summaries; the "Timing Closure Recommendations" panel that would name the
# failing path is HTML-only and does not survive the plain-text export.  This
# re-runs the timing analyzer against the netlist already in db/ — no fit, no
# synthesis, ~1 minute — and writes the full node-by-node path detail.
#
# Usage (from the project root, with quartus_sta on PATH):
#   quartus_sta -t docs/tools/report-timing.tcl
#
# Writes output_files/timing_worst.rpt and echoes the same to the console.

set rev wombat33
if {[llength $quartus(args)] > 0} { set rev [lindex $quartus(args) 0] }

project_open $rev -revision $rev
create_timing_netlist -post_fit
read_sdc
update_timing_netlist

set out output_files/timing_worst.rpt
file delete -force $out

# Worst setup paths across every clock, with the full node-by-node path so the
# offending logic is identifiable by instance name.
report_timing -setup -npaths 20 -detail full_path -stdout -file $out

# Same again restricted to the core machine clock, in case a faster framework
# clock's paths crowd out the core's in the list above.
set core [get_clocks -nowarn {*emu|pll|pll_inst*divclk}]
if {[get_collection_size $core] > 0} {
    report_timing -setup -npaths 10 -detail full_path -to_clock $core \
        -stdout -file $out -append
}

# Endpoint counts per clock: confirms how many paths actually fail.
report_clock_fmax_summary -stdout -file $out -append

delete_timing_netlist
project_close
