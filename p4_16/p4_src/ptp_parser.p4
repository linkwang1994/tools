
#ifndef _PTP_PARSER
#define _PTP_PARSER

#define PTP_FOLLOWUP_DIGEST_TYPE       2
#define PTP_REPLY_DIGEST_TYPE          3
#define PTP_REPLY_FOLLOWUP_DIGEST_TYPE 4


enum bit<16> ether_type_t {
    IPV4  = 0x0800,
    PTP  = 0x88F7
}

struct followup_digest_t {
    bit<16> egress_port;
    bit<48> mac_addr;
    bit<32> timestamp;
}


struct reply_digest_t {
    bit<8>  switch_id;
    bit<32> reference_ts_hi;
    bit<32> reference_ts_lo;
    //bit<16> elapsed_hi;
    bit<32> elapsed_lo;
    bit<32> macts_lo;
    bit<32> egts_lo;
    bit<16> now_igts_hi;
    bit<32> now_igts_lo;
    bit<32> now_macts_lo; 
}

struct reply_followup_digest_t {
    bit<8> switch_id;
    bit<32> tx_capturets_lo;
}


parser PTPIngressParser (
    packet_in pkt, 
    out PTP_t PTP, 
    in bit<16> ethernet_type) {

    state start {
        transition select(ethernet_type) {
            (bit<16>) ether_type_t.PTP : parse_PTP;
            default                     : accept;
        }
    }

    state parse_PTP {
        pkt.extract(PTP);
        transition accept;
    }
}

control PTPIngressDeparser (in bit<48> ethernet_dstAddr, 
    inout PTP_t PTP, 
    in PTP_metadata_t PTP_meta, 
    in ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr) {

    Digest<followup_digest_t>()          PTP_followup_digest;
    Digest<reply_digest_t>()             PTP_reply_digest;
    Digest<reply_followup_digest_t>()    PTP_reply_followup_digest;

    apply {
        if (ig_intr_md_for_dprsr.digest_type == PTP_FOLLOWUP_DIGEST_TYPE) {
            PTP_followup_digest.pack({(bit<16>)PTP_meta.egress_port, ethernet_dstAddr, PTP_meta.ingress_timestamp_clipped});
        }
        if (ig_intr_md_for_dprsr.digest_type == PTP_REPLY_DIGEST_TYPE) {
            PTP_reply_digest.pack({PTP_meta.switch_id,
                                        PTP.reference_ts_hi,
                                        PTP.reference_ts_lo,
                                        //hdr.PTP.igts[47:32],
                                        PTP.igts[31:0],
                                        PTP.igmacts[31:0],
                                        PTP.egts[31:0],
                                        PTP_meta.ingress_timestamp_clipped_hi,
                                        PTP_meta.ingress_timestamp_clipped,
                                        PTP_meta.mac_timestamp_clipped});
        }
        if (ig_intr_md_for_dprsr.digest_type == PTP_REPLY_FOLLOWUP_DIGEST_TYPE) {
            PTP_reply_followup_digest.pack({PTP_meta.switch_id,
                                                PTP.reference_ts_hi});
        }
        //pkt.emit(meta.bridged_header);

        // pkt.emit(meta.bridged_header);
        // pkt.emit(hdr.ethernet);
        // pkt.emit(hdr.ipv4);
        // pkt.emit(hdr.PTP);
    }
}

parser PTPBridgeParser (
    packet_in pkt, 
    out PTP_metadata_t PTP_meta,
    out PTP_bridge_t   bridge) {

    state start {
        pkt.extract(bridge);
#ifdef LOGICAL_SWITCHES
        PTP_meta.switch_id = bridge.switch_id;
#endif
        transition accept;
    }
}

parser PTPEgressParser (
    packet_in pkt, 
    out PTP_t PTP, 
    in bit<16> ethernet_type) {

    state start {
        transition select(ethernet_type) {
            (bit<16>) ether_type_t.PTP : parse_PTP;
            default                     : accept;
        }
    }
    
    
    state parse_PTP {
        pkt.extract(PTP);
        transition accept;
    }
    
}


#endif