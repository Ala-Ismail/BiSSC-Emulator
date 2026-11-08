onerror {quit -code 1}
onbreak {quit -code 1}
set BreakOnAssertion 2
run -all
# A passing test calls std.env.finish; reaching this line means it did not.
quit -code 1
