killall bf_switchd
killall run_switchd



bf_kdrv_mod_load $SDE_INSTALL

/$SDE/../tools/p4_build.sh physic.p4



/$SDE/run_switchd.sh -p physic &

sleep 30


#Config PORTS
/$SDE/run_bfshell.sh -f portConfig 

#Config Tables, Registers etc
/$SDE/run_bfshell.sh -b controlPlane.py 

sleep 10


#rate-show
/$SDE/run_bfshell.sh -f view



killall bf_switchd
