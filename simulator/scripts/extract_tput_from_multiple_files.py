import sys

outfile = open("tput.last", "w")
outfile1 = open("tput.mean", "w")
filenames = ["1", "26", "51", "76", "101", "126", "151", "176", "201", "226", "251", "276", "301", "326", "351", "376", "401", "426", "451", "476", "501"]

for filename in filenames:
    f = open("experiments/"+filename+".dat.out/data/goodput_4.dat", "r")
    for line in f:
        tokens = line.split()
        if tokens[0] == "5":
            outfile.write(filename + " " + str(float(tokens[1])))
            outfile.write("\n")
        if tokens[0] == "avg":
            outfile1.write(filename + " " + str(float(tokens[1])))
            outfile1.write("\n")
    f.close()
outfile.close()
outfile1.close()


