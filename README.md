# Shoal simulator

```shell
$ cd simulator/
```

**Format of tracefile**

Each line should contain the follwing 5 fields comma-separated

```shell
flow-id, src-id, dst-id, flow-size (in bytes), flow-start-time (in seconds)
```

**Processing tracefile**

If the tracefile is in raw-format (i.e. has pkt size in bytes and time in seconds), then first run the preprocessor.
```shell
$ python scripts/tracefile_preprocessor.py -f <path/to/tracefile>
```
    The processed tracefile will be stored in the same directory as the original tracefile with a .processed extension
    
**Compiling the simulator code**
```shell
$ ./compile.sh
```

**Running the simulator code**
```shell
$ ./run.sh -f <filename> [-e <epochs> -w <0/1> -b <link bandwidth> -t <time slot> -c <cell size> -h <header size> -s <short flow size> -l <long flow size> -n <num of flows> -d <percentage failed nodes> -i <interval>][-a -r -p]
-e: to run the exp till specified num of epochs
-w: 1 = static workload; 0 = dynamic workload
-b: link bandwidth in Gbps (float)
-t: length of a time slot in ns (float)
-c: packet(cell) size in Bytes
-h: cell header size in Bytes
-s: small flow size in KB
-l: long flow size in KB
-n: stop experiment after these many flows have finished
-d: percentage failed nodes
-i: interval
-r: to run shoal
-p: to plot graphs
-a: to do both run and plot at once

```
    All the results will be stored in the directory experiments/
    
**Reproducing Shoal results from NSDI'19 paper**

We have added the workloads and scripts to reproduce results from Figures 15 and 18 from our NSDI'19 [paper](https://www.usenix.org/system/files/nsdi19-shrivastav.pdf) at the following location - [workloads.zip](https://drive.google.com/file/d/1uxMs1PzcoAMybahxCpLS-lElIH9a-3iD/view?usp=sharing). To run the experiments,
```shell
$ unzip workloads.zip
```
For Figure 15,
```shell
$ ./workloads/dc_workload/tracefile_preprocessor_batch.sh
$ ./workloads/dc_workload/run_all.sh
$ Results stored in experiments/workloads/dc_workload/
```

For Figure 18,
```shell
$ ./workloads/disaggregated_workload/tracefile_preprocessor_batch.sh
$ ./workloads/disaggregated_workload/run_all.sh
$ Results stored in experiments/workloads/disaggregated_workload/
```

# Shoal FPGA prototype
FPGA implementation of Shoal in Bluespec

## Dependencies
1. connectal
2. fpgamake
3. buildcache [optional]

```shell
$ cd prototype/
```

## How to run
    project_dir = [circuit-switch, shoal-NIC]
### Simulation
```shell
$ cd project_dir/
$ cd bsv/
$ make build.vsim [OR] USE_BUILDCACHE=1 make build.vsim
$ cd vsim/
$ make run <args>
```
### Hardware (Altera DE5 boards)
```shell
$ cd project_dir/<location of Makefile>
$ make build.de5

$jtagconfig -- to get the SERIALNO of the machine to which board is connected

$ SERIALNO=* make run.de5
  [OR] 
$ cd into de5/ and run the below command 
$ quartus_pgm -c SERIALNO -m jtag -o p\;./bin/mkPcieTop.sof

#### On the remote machine to which the board is attached,
- Restart the machine whose board was programmed in the last step
- copy de5/bin/ubuntu.exe to the machine
- make sure connectal/ is present

$ cd connectal/drivers/pcieportal/
$ make
$ sudo insmod pcieportal.ko

- Verify the output of ls /dev/portal*
/dev/portal_b0t0p1  /dev/portal_b0t0p3  /dev/portal_b0t1p5  /dev/portal_b1t0p1  /dev/portal_b1t0p3  /dev/portal_b1t1p5
/dev/portal_b0t0p2  /dev/portal_b0t0p4  /dev/portal_b0t1p6  /dev/portal_b1t0p2  /dev/portal_b1t0p4  /dev/portal_b1t1p6
If there are 2 boards. b0 = board 1, b1 = board 2.

$ FPGA_NUMBER=* ./ubuntu.exe <args>   [FPGA_NUMBER value starts with 0]
```

### Debugging timing constraint violations (using Quartus tool)
```shell
$ quartus de5/mkPcieTop.qpf (then go to tools -> timing)
```
