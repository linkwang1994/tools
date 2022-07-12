
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "ptp_headers.p4"
#include "ptp_parser.p4"

#define COMMAND_PTP_REQUEST 0x2
#define COMMAND_PTP_RESPONSE 0x3

#define COMMAND_PTP_FOLLOWUP 0x6
#define COMMAND_PTPS2S_GENREQUEST 0x11
#define COMMAND_PTPS2S_REQUEST 0x12
#define COMMAND_PTPS2S_RESPONSE 0x13

#define MAX_32BIT 4294967295
#define MAX_LINKS 512

#define SWITCH_CPU 192

#ifdef LOGICAL_SWITCHES
#define MAX_SWITCHES 16
#else
#define MAX_SWITCHES 1
#endif


control virtSwitch(inout PTP_t PTP_hdr, 
    inout PTP_metadata_t PTP_meta,
    in bit<48> ethernet_srcAddr,
    in bit<48> ethernet_dstAddr,
    in bit<16> ethernet_etherType,     
    in PortId_t ingress_port, 
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr) {

    action _drop() {
        ig_intr_md_for_dprsr.drop_ctl = 1;
    }

    action nop() {}

    action classify_switch (bit<8> switch_id) {
        PTP_meta.switch_id = switch_id;
    }
    
    action classify_src_switch (bit<8> switch_id) {
        PTP_meta.src_switch_id = switch_id;
    }

    table acl {
        actions = {
            _drop();
            nop();

        }
        key = {
            ingress_port: exact;
            ethernet_dstAddr   : exact;
            ethernet_etherType : exact;
        }
        default_action = nop();
    }
    
    table classify_logical_switch {
        actions = {
            classify_switch();
            nop();
        }
        key = {
            ethernet_dstAddr: exact;
        }
        default_action = nop();
    }
    
    table classify_src_logical_switch {
        actions = {
            classify_src_switch();
            nop();
        }
        key = {
            ethernet_srcAddr: exact;
        }
        default_action = nop();
    }
    
    apply {
        acl.apply();
        if (PTP_hdr.isValid()) {
            classify_logical_switch.apply();
            classify_src_logical_switch.apply();
        }
    }

}


Register<bit<32>, bit<32>>(MAX_SWITCHES) ts_hi;

Register<bit<32>, bit<32>>(MAX_SWITCHES) ts_lo;

Register<bit<32>, bit<32>>(1) PTP_now_hi;

Register<bit<32>, bit<32>>(1) PTP_now_lo;

Register<bit<16>, bit<16>>(MAX_SWITCHES) timesyncs2s_igts_hi;

control PTPNow (inout PTP_metadata_t PTP_meta, in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_parser_aux) {
    RegisterAction<bit<32>, bit<8>, bit<32>>(ts_hi) ts_hi_get = {
        void apply (inout bit<32> value, out bit<32> result) {  
            result = value;
        }
    };

    RegisterAction<bit<32>, bit<8>, bit<32>>(ts_lo) ts_lo_get = {
        void apply (inout bit<32> value, out bit<32> result) {
            result = value;
        }
    };

    RegisterAction<bit<16>, bit<8>, bit<16>>(timesyncs2s_igts_hi) timesyncs2s_igts_hi_set = {
        void apply(inout bit<16> value, out bit<16> result) {
            value = (bit<16>)ig_intr_md_from_parser_aux.global_tstamp[47:32];
            result = value;
        }
    }; 

    action timesyncs2s_capture_igTs_hi() {
        PTP_meta.ingress_timestamp_clipped_hi = (bit<16>)timesyncs2s_igts_hi_set.execute(0);
    }
    action timesync_hi_request() {
        PTP_meta.reference_ts_hi = ts_hi_get.execute(PTP_meta.switch_id);
    }

    action timesync_request() {
        PTP_meta.reference_ts_lo = ts_lo_get.execute(PTP_meta.switch_id);
    }

    action do_PTP_compare_residue() {
        PTP_meta.PTP_overflow_compare = (PTP_meta.PTP_residue <= PTP_meta.ingress_timestamp_clipped ? PTP_meta.PTP_residue : PTP_meta.ingress_timestamp_clipped);
    }

    action do_PTP_handle_overflow () {
        PTP_meta.PTP_now_hi = PTP_meta.PTP_now_hi + 1;
    }
    
    action nop () {

    }
    
    table PTP_handle_overflow {
        actions = {
            do_PTP_handle_overflow();
            nop();
        }
        key = {
            PTP_meta.PTP_compare_residue: exact;
        }
        size = 1;
        default_action = do_PTP_handle_overflow();
    }

    apply {
                  
        timesyncs2s_capture_igTs_hi();
        PTP_meta.ingress_timestamp_clipped = (bit<32>)ig_intr_md_from_parser_aux.global_tstamp[31:0];
        timesync_hi_request();
        timesync_request();        
        PTP_meta.PTP_now_lo = PTP_meta.reference_ts_lo + PTP_meta.ingress_timestamp_clipped;
        PTP_meta.PTP_now_hi = PTP_meta.reference_ts_hi + (bit<32>)PTP_meta.ingress_timestamp_clipped_hi;
        PTP_meta.PTP_residue = MAX_32BIT - PTP_meta.reference_ts_lo;
        do_PTP_compare_residue();
        PTP_meta.PTP_compare_residue = PTP_meta.ingress_timestamp_clipped - PTP_meta.PTP_overflow_compare;
        PTP_handle_overflow.apply();
    }
}


#ifdef PTP_CALC_DP // Used to perform PTP time correction/calculation in the Data-plane

Register<bit<32>, bit<32>>(MAX_SWITCHES) PTP_reqmacdelay;

Register<bit<32>, bit<32>>(MAX_SWITCHES) PTP_respigts;

Register<bit<32>, bit<32>>(MAX_SWITCHES) PTP_respnow_hi;

Register<bit<32>, bit<32>>(MAX_SWITCHES) PTP_respnow_lo;

control PTPRespStore (inout PTP_t PTP_hdr, inout PTP_metadata_t PTP_meta) {
    
    RegisterAction<bit<32>, bit<8>, bit<32>>(PTP_reqmacdelay) PTP_reqmacdelay_set = {
        void apply(inout bit<32> value) {
            value = (bit<32>)PTP_hdr.igmacts;
        }
    };

    RegisterAction<bit<32>, bit<8>, bit<32>>(PTP_respigts) PTP_respigts_set = {
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>)PTP_hdr.igts;
        }
    };    

    RegisterAction<bit<32>, bit<8>, bit<32>>(PTP_respnow_hi) PTP_respnow_hi_set = {
        void apply(inout bit<32> value) {
            value = PTP_hdr.reference_ts_hi;
        }
    };

    RegisterAction<bit<32>, bit<8>, bit<32>>(PTP_respnow_lo) PTP_respnow_lo_set = {
        void apply(inout bit<32> value) {
            value = PTP_hdr.reference_ts_lo;
        }
    };
    
    action PTP_store_reqmacdelay (bit<8> switch_id) {
        PTP_reqmacdelay_set.execute(switch_id);
    }
    
    action PTP_store_respigts () {
        PTP_respigts_set.execute(PTP_meta.switch_id);
    }

    action PTP_store_reference_hi () {
        PTP_respnow_hi_set.execute(PTP_meta.switch_id);
    }
    
    action PTP_store_reference_lo () {
        PTP_respnow_lo_set.execute(PTP_meta.switch_id);
    }LOGICAL_SWITCHES
    
    apply {
  
        PTP_store_reference_hi();
        PTP_store_reference_lo();
        PTP_store_reqmacdelay();
        PTP_store_respigts();
    }
}

control PTPCorrect (inout PTP_t PTP_hdr, inout PTP_metadata_t PTP_meta) {

    apply {

    }
}
#endif

control PTPIngress(
    inout PTP_t PTP_hdr, 
    inout bit<48> ethernet_srcAddr,
    inout bit<48> ethernet_dstAddr,
    inout PTP_metadata_t PTP_meta, 
    inout PTP_bridge_t bridge, 
    in ingress_intrinsic_metadata_t ig_intr_md, 
    in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_parser_aux, 
    out ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr, 
    out ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm) {

    RegisterAction<bit<32>, bit<1>, bit<32>>(PTP_now_hi) PTP_now_hi_set = {
        void apply(inout bit<32> value) {
            value = PTP_meta.PTP_now_hi;
        }
    };
    
    RegisterAction<bit<32>, bit<1>, bit<32>>(PTP_now_lo) PTP_now_lo_set = {
        void apply(inout bit<32> value) {
            value = PTP_meta.PTP_now_lo;
        }
    };

    action _drop() {
        ig_intr_md_for_dprsr.drop_ctl = 1;
    }

    action nop() {}
    
    action fill_PTP_packet() {
        PTP_hdr.reference_ts_lo = PTP_meta.PTP_now_lo;
        PTP_hdr.reference_ts_hi = PTP_meta.PTP_now_hi;
        PTP_hdr.igmacts = ig_intr_md.ingress_mac_tstamp;
        PTP_hdr.igts = ig_intr_md_from_parser_aux.global_tstamp;
    }
    
    action do_PTP_store_now_hi() {
        PTP_now_hi_set.execute(0);
    }

    action do_PTP_store_now_lo() {
        PTP_now_lo_set.execute(0);
    }
    
    action reverse_packet() {
        ethernet_dstAddr = ethernet_srcAddr;
        ethernet_srcAddr = 48w0x11;
    }

    action do_qos() {
        ig_intr_md_for_tm.qid = 5w3;
    }
    
    action timesync_flag_cp_learn() {
        ig_intr_md_for_dprsr.digest_type = PTP_FOLLOWUP_DIGEST_TYPE;
    }    
    
    table PTP_store_now_hi {
        actions = {
            do_PTP_store_now_hi();
        }
        default_action = do_PTP_store_now_hi();
    }
    
    table PTP_store_now_lo {
        actions = {
            do_PTP_store_now_lo();
        }
        default_action = do_PTP_store_now_lo();
    }
    
    table dropit {
        actions = {
            _drop();
        }
        default_action = _drop();
    }

    apply {
        if (PTP_hdr.command == COMMAND_PTPS2S_RESPONSE) {
#ifdef PTP_CALC_DP
            // PTP Reference Adjustment in the data-plane.
            PTPRespStore.apply();
#else
            // Send a Digest to control-plane for PTP Reference Adjustment
            PTP_meta.mac_timestamp_clipped = (bit<32>)ig_intr_md.ingress_mac_tstamp[31:0];
            ig_intr_md_for_dprsr.digest_type = PTP_REPLY_DIGEST_TYPE;
            _drop();
#endif
            // Send Digest to Control-plane along with reply details
        } else if (PTP_hdr.command == COMMAND_PTP_FOLLOWUP) {
            if (ig_intr_md.ingress_port != SWITCH_CPU) {
#ifdef PTP_CALC_DP
                //PTP Reference Adjustment in the data-plane.
                PTPCorrect.apply();
#else
                // Send Digest to Control-plane along with reply details for Time calculation.
                ig_intr_md_for_dprsr.digest_type = PTP_REPLY_FOLLOWUP_DIGEST_TYPE;
                _drop();
#endif
            }
        }

        if (PTP_hdr.command == COMMAND_PTP_REQUEST || PTP_hdr.command == COMMAND_PTPS2S_REQUEST) {
            reverse_packet();
            fill_PTP_packet();
            ig_intr_md_for_dprsr.digest_type = PTP_FOLLOWUP_DIGEST_TYPE;
        }
#ifdef LOGICAL_SWITCHES        
        bridge.switch_id = PTP_meta.switch_id;
#endif // LOGICAL_SWITCHES
        bridge.setValid();
        bridge.ingress_port = ig_intr_md.ingress_port;
        do_qos();
    }
}


#ifdef LOGICAL_SWITCHES
Register<bit<32>, bit<32>>(MAX_LINKS) current_utilization;
#endif // LOGICAL_SWITCHES
Register<bit<32>, bit<32>>(MAX_SWITCHES) timesyncs2s_reqts_lo;

control PTPEgress(
    inout PTP_t PTP_hdr, 
    inout PTP_metadata_t PTP_meta, 
    inout PTP_bridge_t bridge,
    in egress_intrinsic_metadata_t eg_intr_md, 
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_parser_aux,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_md_for_oport) {

    Lpf<bit<16>, bit<9>>(MAX_LINKS) current_utilization_bps;

#ifdef LOGICAL_SWITCHES
    RegisterAction<bit<32>, bit<9>, bit<32>>(current_utilization) set_current_utilization = {
        void apply(inout bit<32> value) {
            bit<32> in_value;
            in_value = value;
            value = PTP_meta.current_utilization;
        }
    };
#endif // LOGICAL_SWITCHES    

    RegisterAction<bit<32>, bit<32>, bit<32>>(timesyncs2s_reqts_lo) timesyncs2s_reqts_lo_set = {
        void apply(inout bit<32> value) {
            bit<32> in_value;
            in_value = value;
            value = (bit<32>)eg_intr_md_from_parser_aux.global_tstamp;
        }
    };
    
    /*** Actions ***/

    action do_calc_host_rate () {
        PTP_meta.current_utilization = (bit<32>)current_utilization_bps.execute(eg_intr_md.pkt_length, bridge.ingress_port);
    }

    action nop () {}

#ifdef LOGICAL_SWITCHES
    action do_store_current_utilization () {
        set_current_utilization.execute(bridge.ingress_port);
    }
#endif // LOGICAL_SWITCHES

    action do_PTP_capture_tx () {
        eg_intr_md_for_oport.capture_tstamp_on_tx = 1;
    }
    action do_PTP_response () {
        PTP_hdr.command = COMMAND_PTP_RESPONSE;
        PTP_hdr.egts = eg_intr_md_from_parser_aux.global_tstamp;
        PTP_hdr.current_rate = PTP_meta.current_utilization;
    }
    action do_PTPs2s_request () {
        PTP_hdr.command = COMMAND_PTPS2S_REQUEST;
    }
    action do_PTPs2s_response () {
        PTP_hdr.command = COMMAND_PTPS2S_RESPONSE;
        PTP_hdr.egts = eg_intr_md_from_parser_aux.global_tstamp;
    }

    apply {
        do_calc_host_rate();
        if (PTP_hdr.command != COMMAND_PTP_FOLLOWUP) {
            do_PTP_capture_tx();
        }
        if (PTP_hdr.command == COMMAND_PTPS2S_REQUEST) {
            do_PTPs2s_response();
        } else if (PTP_hdr.command == COMMAND_PTP_REQUEST) {
            do_PTP_response();
        } else if (PTP_hdr.command == COMMAND_PTPS2S_GENREQUEST) {
            do_PTPs2s_request();
        }       
    }
}

