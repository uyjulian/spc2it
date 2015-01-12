#####################################################
#Part of SPC2IT, read readme.md for more information#
#####################################################

OBJDIR = ./_obj/
EXENAME = spc2it
OBJS = $(addprefix $(OBJDIR), emu.o it.o main.o sound.o spc700.o)
COMMONFLAGS = 
CFLAGS = $(COMMONFLAGS) -Wall -g 
LDFLAGS = $(OBJS) -o $(EXENAME) $(COMMONFLAGS) -lm -g 
LD = gcc $(LDFLAGS) 
CC = gcc $(CFLAGS)

.PHONY: clean all

all: $(EXENAME)

$(EXENAME): $(OBJDIR) $(OBJS)
	$(LD)
$(OBJDIR)emu.o: emu.c it.h emu.h sound.h sneese_spc.h spc2ittypes.h
	$(CC) -c emu.c -o $(OBJDIR)emu.o
$(OBJDIR)it.o: it.c it.h emu.h sound.h sneese_spc.h spc2ittypes.h
	$(CC) -c it.c -o $(OBJDIR)it.o
$(OBJDIR)main.o: main.c it.h emu.h sound.h sneese_spc.h spc2ittypes.h
	$(CC) -c main.c -o $(OBJDIR)main.o
$(OBJDIR)sound.o: sound.c emu.h sound.h it.h sneese_spc.h spc2ittypes.h
	$(CC) -c sound.c -o $(OBJDIR)sound.o
$(OBJDIR)spc700.o: spc700.c sneese_spc.h
	$(CC) -c spc700.c -o $(OBJDIR)spc700.o
$(OBJDIR):
	mkdir -p $(OBJDIR)
clean:
	rm -rf *~ $(OBJDIR) $(EXENAME)
