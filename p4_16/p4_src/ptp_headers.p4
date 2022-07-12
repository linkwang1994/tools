
#ifndef _PTP_HEADERS
#define _PTP_HEADERS

// TODO : Below PTP header is not entirely compatible with IEEE 1588
header PTP_t {
    bit<16> magic;           
    bit<8>  command;         
    bit<32> reference_ts_hi; // Current Time Hi
    bit<32> reference_ts_lo; // Current Time Lo
    bit<32> current_rate;    // Traffic rate used for NIC profiling
    bit<48> igmacts;         // Mac     Timestamp
    bit<48> igts;            // Ingress Timestamp 
    bit<48> egts;            // Egress  Timestamp
}

header PTP_bridge_t {
#ifdef LOGICAL_SWITCHES
    bit<8> switch_id;
#endif // LOGICAL_SWITCHES
    PortId_t ingress_port;
    bit<7> _pad0;
}

header transparent_clock_t {
    bit<8>  udp_chksum_offset;
    bit<8>  elapsed_time_offset;
    bit<48> captureTs;
}

struct PTP_metadata_t {
    bit<32> reference_ts_hi;
    bit<32> reference_ts_lo;
    bit<32> mac_timestamp_clipped;
    bit<16> ingress_timestamp_clipped_hi;
    bit<32> ingress_timestamp_clipped;
    bit<32> reqdelay;
    bit<8>  switch_id;
    bit<8>  src_switch_id;
    bit<32> current_utilization;
    bit<32> PTP_now_hi;
    bit<32> PTP_now_lo;
    PortId_t egress_port;
    bit<32> PTP_residue;
    bit<32> PTP_compare_residue;
    bit<1>  PTP_overflow;
    bit<32> PTP_overflow_compare;
}


#endif