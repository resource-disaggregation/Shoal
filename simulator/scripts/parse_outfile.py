import sys

index = sys.argv[1]

inp = open('logs/out_shoal_sim_log_flows_tcp_load-'+str(index)+'-reactive-app.stdout.txt', 'r')
out1 = open('system_tput', 'a')
out2 = open('queue_len_999', 'a')

for line in inp:
    tokens = line.split(' ')
    if (tokens[0] == 'System'):
        tokens1 = tokens[7].split('/')
        out1.write(str(tokens1[1])+' ')
        #out1.write('\n')
    elif (tokens[0] == '99.9th'):
        out2.write(str(index)+',')
        out2.write(str(tokens[3])+' ')
        #out2.write('\n')

inp.close()
out1.close()
out2.close()
