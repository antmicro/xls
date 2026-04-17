PML_FILE ?= model.pml
PAN_EXE = pan
CC = gcc
CFLAGS = -O3 -DSAFETY

all: sim

sim:
	spin $(PML_FILE)

sim_verbose:
	spin -p -l $(PML_FILE)

verify:
	spin -a $(PML_FILE)
	$(CC) $(CFLAGS) -o $(PAN_EXE) pan.c
	./$(PAN_EXE)

trail:
	spin -t -p -l $(PML_FILE)

clean:
	rm -f pan.* $(PAN_EXE) *.trail

.PHONY: all sim verify trail clean
