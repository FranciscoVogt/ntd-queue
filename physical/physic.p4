#include <tna.p4>

typedef bit<48> mac_addr_t;
typedef bit<12> vlan_id_t;
typedef bit<16> ether_type_t;
typedef bit<32> ipv4_addr_t;

const ether_type_t ETHERTYPE_IPV4 = 16w0x0800;
const ether_type_t ETHERTYPE_VLAN = 16w0x8100;


const ether_type_t ETHERTYPE_MONITOR = 0x1234;

header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    bit<16> ether_type;
}

header vlan_tag_h {
    bit<3> pcp;
    bit<1> cfi;
    vlan_id_t vid;
    bit<16> ether_type;
}

header ipv4_h {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> total_len;
    bit<16> identification;
    bit<16> flags;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdr_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}


header monitor_h {
	bit<32> qID;
	bit<32> enqDepth;
	bit<32> deqDepth;	
	bit<32> enqTime;
	bit<32> deqTime;
	bit<32> reportTime;

}

struct headers {
    pktgen_timer_header_t timer;
    ethernet_h	ethernet;
    monitor_h	mon;
    vlan_tag_h	vlan_tag;
    ipv4_h		ipv4;
}

struct my_ingress_metadata_t {
    bit<8> ctrl;
    MirrorId_t session_ID;
}

struct my_egress_metadata_t {
	bit<32> qID;
	bit<32> enqDepth;
	bit<32> deqDepth;	
	bit<32> enqTime;
	bit<32> deqTime;
}

parser SwitchIngressParser(
    packet_in packet, 
    out headers hdr, 
    out my_ingress_metadata_t ig_md,
    out ingress_intrinsic_metadata_t ig_intr_md) {

    state start {
        packet.extract(ig_intr_md);
        packet.advance(PORT_METADATA_SIZE);

        transition parse_ethernet;
    }


    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4:  parse_ipv4;
            ETHERTYPE_VLAN:  parse_vlan;
            ETHERTYPE_MONITOR: parse_monitor;
            default: accept;
        }
    }
    
    state parse_monitor {
		packet.extract(hdr.mon);
		transition accept;
	}

    state parse_vlan {
        packet.extract(hdr.vlan_tag);
        transition select(hdr.vlan_tag.ether_type) {
            ETHERTYPE_IPV4:  parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

control SwitchIngress(
    inout headers hdr, 
    inout my_ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_tm_md) {

    action drop() {
        ig_intr_dprsr_md.drop_ctl = 0x1;
    }

    action send(PortId_t port) {
        //define output port
        ig_intr_tm_md.ucast_egress_port = port;
        
        //define that mirror will happen and the mirror session ID
        ig_intr_dprsr_md.mirror_type = 2;
        ig_md.session_ID = 1;
        
    }
    
    action multicast(MulticastGroupId_t mcast_grp) {
        ig_intr_tm_md.mcast_grp_b = mcast_grp;
    }

    table fwd {
        key = {
            ig_intr_md.ingress_port	:	exact;
        }
        actions = {
            send;
            multicast;
            drop;
        }
        const default_action = drop();
        size = 1024;
    }

    apply {

        fwd.apply();

    }

}

control SwitchIngressDeparser(
    packet_out pkt,
    inout headers hdr,
    in my_ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md) {


	Mirror() mirror;

    apply {
        pkt.emit(hdr);
        
        if(ig_intr_dprsr_md.mirror_type == 2){
			mirror.emit(ig_md.session_ID);
		}
    }
}

parser SwitchEgressParser(
    packet_in packet,
    out headers hdr,
    out my_egress_metadata_t eg_md,
    out egress_intrinsic_metadata_t eg_intr_md) {

    state start {
        packet.extract(eg_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4:  parse_ipv4;
            ETHERTYPE_VLAN:  parse_vlan;
            ETHERTYPE_MONITOR: parse_monitor;
            default: accept;
        }
    }
    
    state parse_monitor {
		packet.extract(hdr.mon);
		transition accept;
	}

    state parse_vlan {
        packet.extract(hdr.vlan_tag);
        transition select(hdr.vlan_tag.ether_type) {
            ETHERTYPE_IPV4:  parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

typedef bit<32> reg_index_t;

control SwitchEgress(
    inout headers hdr,
    inout my_egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t ig_intr_dprs_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_oport_md) {


	/* save the enqueue depth */
	Register<bit<32>, reg_index_t>(32) reg_enqDepth;
	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_enqDepth) write_enqDepth = {
		void apply(inout bit<32> value, out bit<32> result) {		
			value = eg_md.enqDepth;
		}
	};

	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_enqDepth) read_enqDepth = {
		void apply(inout bit<32> value, out bit<32> result) {	
			result = value;
		}
	};
	
	/* save the dequeue depth */
	Register<bit<32>, reg_index_t>(32) reg_deqDepth;
	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_deqDepth) write_deqDepth = {
		void apply(inout bit<32> value, out bit<32> result) {		
			value = eg_md.deqDepth;
		}
	};

	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_deqDepth) read_deqDepth = {
		void apply(inout bit<32> value, out bit<32> result) {	
			result = value;
		}
	};
	
	
	/* save the enqueue time */ 
	Register<bit<32>, reg_index_t>(32) reg_enqTime;
	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_enqTime) write_enqTime = {
		void apply(inout bit<32> value, out bit<32> result) {		
			value = eg_md.enqTime;
		}
	};

	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_enqTime) read_enqTime = {
		void apply(inout bit<32> value, out bit<32> result) {	
			result = value;
		}
	};
	
	/* save the dequeue time */ 
	Register<bit<32>, reg_index_t>(32) reg_deqTime;
	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_deqTime) write_deqTime = {
		void apply(inout bit<32> value, out bit<32> result) {		
			value = eg_md.deqTime;
		}
	};

	RegisterAction<bit<32>, reg_index_t, bit<32>>(reg_deqTime) read_deqTime = {
		void apply(inout bit<32> value, out bit<32> result) {	
			result = value;
		}
	};


    apply {

		//collect the information
		if (hdr.ether_type == ETHERTYPE_MONITOR){
		
			
			
			hdr.mon.deqTime = read_deqTime.execute(hdr.mon.qID);
			hdr.mon.enqTime = read_enqTime.execute(hdr.mon.qID);
			
			hdr.mon.deqDepth = read_deqDepth.execute(hdr.mon.qID);
			hdr.mon.enqDepth = read_enqDepth.execute(hdr.mon.qID);
			
			hdr.mon.reportTime = (bit<32>)eg_intr_md_from_prsr.global_tstamp;
			
		
		}
		//write information
		else if (eg_intr_md.egress_port== 180){
		
			eg_md.qID = (bit<32>)eg_intr_md.egress_qid;
			eg_md.enqDepth = (bit<32>)eg_intr_md.enq_qdepth;
			eg_md.deqDepth = (bit<32>)eg_intr_md.deq_qdepth;	
			eg_md.enqTime = (bit<32>)eg_intr_md.enq_tstamp;
			eg_md.deqTime = (bit<32>)eg_intr_md_from_prsr.global_tstamp;
			
			write_deqTime.execute(eg_md.qID);
			write_enqTime.execute(eg_md.qID);
			
			write_deqDepth.execute(eg_md.qID);
			write_enqDepth.execute(eg_md.qID);
		
		
		
		}

    }
}

control SwitchEgressDeparser(
    packet_out pkt,
    inout headers hdr,
    in my_egress_metadata_t eg_md,
    in egress_intrinsic_metadata_for_deparser_t ig_intr_dprs_md) {
    apply {
        pkt.emit(hdr);
    }
}

Pipeline(SwitchIngressParser(),
        SwitchIngress(),
        SwitchIngressDeparser(),
        SwitchEgressParser(),
        SwitchEgress(),
        SwitchEgressDeparser()) pipe;

Switch(pipe) main;
