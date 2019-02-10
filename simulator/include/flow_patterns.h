#ifndef __FLOW_PATTERNS_H__
#define __FLOW_PATTERNS_H__

#include <stdint.h>

#include "node.h"
#include "driver.h"

typedef void (*add_host_flows_t)(node_t);

void read_from_tracefile();
void tracefile(node_t);

#endif
