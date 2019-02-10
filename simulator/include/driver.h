#ifndef __DRIVER_H__
#define __DRIVER_H__

extern node_t* nodes;
extern volatile int64_t curr_timeslot;
extern volatile int64_t curr_epoch;
extern int8_t flow_trace_scanned_completely;
extern char* ptr;
extern int64_t flows_started_in_epoch;
extern float percentage_failed_nodes;

#endif
