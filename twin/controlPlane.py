#from netaddr import IPAddress
p4 = bfrt.ndt.pipe

fwd_table = p4.SwitchIngress.fwd


fwd_table.add_with_multicast(ingress_port=160, mcast_grp=1)


fwd_table.add_with_send(ingress_port=130, port=130)

fwd_table.add_with_send(ingress_port=52, port=152)
fwd_table.add_with_send(ingress_port=44, port=144)

#multicast configs

PRE = bfrt.pre

#PRE.node.entry(1, 10, [], [144,152]).push()
PRE.node.entry(1, 10, [], [44,52]).push()

PRE.mgid.entry(1, [1], [False], [0]).push()


bfrt.complete_operations()
