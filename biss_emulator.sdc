create_clock -name clk_75m -period 13.333 [get_ports {clk_75m}]
derive_clock_uncertainty
# External interface delays depend on the board and master and are not yet set.
# MA is asynchronous and passes through ma_meta/ma_sync in biss_frame_engine.
set_false_path -from [get_ports {ma_in}] -to [get_registers {*|ma_meta}]
