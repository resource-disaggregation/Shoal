# Shoal simulator

**Format of tracefile**

Each line should contain the follwing 5 fields comma-separated

*flow-id, src-id, dst-id, flow-size (in bytes), flow-start-time (in seconds)*

```shell
     $ cd shoal-simulator/
```

```shell
     $ mkdir traces
```
Put all the tracefiles in that directory.

1)  If the tracefile is in raw-format (i.e. has pkt size in bytes and time in seconds), then first run the preprocessor.
```shell
     $ python scripts/tracefile_preprocessor.py -f <raw tracefile>
```
    The processed tracefile will be stored in the traces/ directory with .processed extension
    
2)  Compile the code
```shell
     $ ./compile.sh
```

3) Now we are ready to run the simulator
```shell
     $ ./run.sh -f <processed tracefilepath> [-e <epochs> -w <0/1> -b <link bandwidth> -t <time slot> -c <cell size> -h <header size> -s <short flow size> -l <long flow size> -n <num of flows>] [-r -p -a]
    -e: to run the exp till specified num of epochs
    -w: 1 = static workload; 0 = dynamic workload
    -b: link bandwidth in Gbps (float)
    -t: length of a time slot in ns (float)
    -c: packet(cell) size in Bytes
    -h: cell header size in Bytes
    -s: small flow size in KB
    -l: long flow size in KB
    -n: stop experiment after these many flows have finished
    -r: to run shoal
    -p: to plot graphs
    -a: to do both run and plot at once
```
    All the results will be stored in the directory experiments/

# Shoal FPGA prototype
FPGA implementation of Shoal in Bluespec

## Dependencies
1. connectal
2. fpgamake
3. buildcache [optional]

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
