#!/bin/bash

[ -f hpretl_tt03_temperature_sensor.mag ] && rm hpretl_tt03_temperature_sensor.mag
[ -f pretl_tt03_temperature_sensor.pex.spice ] && rm pretl_tt03_temperature_sensor.pex.spice

# Run OpenLane flow to build layout
flow.tcl -design ../src -tag foo -overwrite
cp ../src/runs/foo/results/final/mag/hpretl_tt03_temperature_sensor.mag .

# Extract netlist from layout
iic-pex.sh -m 1 -s 1 hpretl_tt03_temperature_sensor.mag

# Get rid of MOSFET for decoupling
TMP=tmp.spice
mv hpretl_tt03_temperature_sensor.pex.spice $TMP
cat $TMP | grep -v "vccd1 vssd1 vccd1 vccd1" | grep -v "vssd1 vccd1 vssd1 vssd1" > hpretl_tt03_temperature_sensor.pex.spice
rm $TMP
