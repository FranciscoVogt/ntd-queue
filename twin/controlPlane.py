#from netaddr import IPAddress
p4 = bfrt.ntd.pipe

fwd_table = p4.SwitchIngress.fwd


fwd_table.add_with_multicast(ingress_port=164, mcast_grp=1)




#multicast configs

PRE = bfrt.pre

PRE.node.entry(1, 10, [], [164,172]).push()

PRE.mgid.entry(1, [1], [False], [0]).push()


bfrt.complete_operations()
