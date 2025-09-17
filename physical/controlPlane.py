#from netaddr import IPAddress
p4 = bfrt.physic.pipe

fwd_table = p4.SwitchIngress.fwd


fwd_table.add_with_send(ingress_port=172, port=172)

mir = bfrt.mirror

mir.cfg.entry_with_normal(sid = 1, direction = 'BOTH', session_enable = True, ucast_egress_port = 164, ucast_egress_port_valid = 1).push()


#multicast configs



bfrt.complete_operations()
