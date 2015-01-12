/****************************************************
*Part of SPC2IT, read readme.md for more information*
****************************************************/

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

#include "sound.h"
#include "it.h"
#include "emu.h"
#include "sneese_spc.h"

#ifdef _WIN32
#undef realpath
#define realpath(N,R) _fullpath((R),(N),_MAX_PATH)
#endif

void Usage()
{
	printf("Usage: spc2it [options] <filename>\n");
	printf("Where <filename> is any .spc or .sp# file\n\n");
	printf("Available switches:\n");
	printf("    -t x        Specify a time limit in seconds         [60 default]\n");
	printf("    -d xxxxxxxx Voices to disable (1-8)                 [none default]\n");
	printf("    -r xxx      Specify IT rows per pattern             [200 default]\n");
}

void CheckSizes() {
	size_t u8Size = sizeof(u8);
	if (!(u8Size == 1))
		printf("Warning: wrong size u8: %lu \n", u8Size);
	size_t u16Size = sizeof(u16);
	if (!(u16Size == 2))
		printf("Warning: wrong size u16: %lu \n", u16Size);
	size_t u32Size = sizeof(u32);
	if (!(u32Size == 4))
		printf("Warning: wrong size u32: %lu \n", u32Size);
	size_t u64Size = sizeof(u64);
	if (!(u64Size == 8))
		printf("Warning: wrong size u64: %lu \n", u64Size);
	size_t s8Size = sizeof(s8);
	if (!(s8Size == 1))
		printf("Warning: wrong size s8: %lu \n", s8Size);
	size_t s16Size = sizeof(s16);
	if (!(s16Size == 2))
		printf("Warning: wrong size s16: %lu \n", s16Size);
	size_t s32Size = sizeof(s32);
	if (!(s32Size == 4))
		printf("Warning: wrong size s32: %lu \n", s32Size);
	size_t s64Size = sizeof(s64);
	if (!(s64Size == 8))
		printf("Warning: wrong size s64: %lu \n", s64Size);
	size_t ITFileHeaderSize = sizeof(ITFileHeader);
	if (!(ITFileHeaderSize == 192))
		printf("Warning: wrong size ITFileHeader: %lu \n", ITFileHeaderSize);
	size_t ITFileSampleSize = sizeof(ITFileSample);
	if (!(ITFileSampleSize == 80))
		printf("Warning: wrong size ITFileSample: %lu \n", ITFileSampleSize);
	size_t ITFilePatternSize = sizeof(ITFilePattern);
	if (!(ITFilePatternSize == 8))
		printf("Warning: wrong size ITFilePattern: %lu \n", ITFilePatternSize);
	size_t SPCFileSize = sizeof(SPCFile);
	if (!(SPCFileSize == 65920))
		printf("Warning: wrong size SPCFile: %lu \n", SPCFileSize);
}

int main(int argc, char **argv)
{
	CheckSizes();
	s32 seconds, limit, done;
	char fn[PATH_MAX];
	s32 i;
	fn[0] = 0;
	ITrows = 200; // Default 200 IT rows/pattern
	limit = 0;    // Will be set later
	for (i = 1; i < argc; i++)
	{
		if (argv[i][0] == '-')
			switch (argv[i][1])
			{
			case 'r':
				i++;
				ITrows = atoi(argv[i]);
				break;
			case 't':
				i++;
				limit = atoi(argv[i]);
				break;
			default:
				printf("Warning: unrecognized option '-%c'\n", argv[i][1]);
			}
		else
			realpath(argv[i], fn);
	}
	if (fn[0] == 0)
	{
		Usage();
		exit(0);
	}
	printf("\nFilepath:            %s\n", fn);
	if (ITStart())
	{
		printf("Error: failed to init pattern buffers\n");
		exit(1);
	}
	if (SPCInit(fn)) // Reset SPC and load state
	{
		printf("Error: failed to initialize emulation\n");
		exit(1);
	}
	if (SNDInit())
	{
		printf("Error: init sound failed\n");
		exit(1);
	}

	if ((!limit) && (SPCtime))
		limit = SPCtime;
	else
		limit = 60;

	printf("Time (seconds):      ");

	if (limit)
		printf("%i\n", limit);
	else
		printf("none\n");

	printf("IT Parameters:\n");
	printf("    Rows/pattern:    %d\n", ITrows);

	printf("ID info:\n");
	printf("    Song name:       %s\n", SPCInfo->SongTitle);
	printf("    Game name:       %s\n", SPCInfo->GameTitle);
	printf("    Dumper:          %s\n", SPCInfo->DumperName);
	printf("    Comments:        %s\n", SPCInfo->Comment);
	printf("    Dumped on date:  %s\n", SPCInfo->Date);

	printf("\n  Progress: \n");

	fflush(stdout);

	seconds = SNDratecnt = done = 0;

	while (!done)
	{
		ITMix();
		if (ITUpdate())
			break;
		SNDMix(); // run the SPC


		if (SNDratecnt >= 100)
		{
			SNDratecnt -= 100;
			seconds++; // count number of seconds
			printf("%f ", (f64)seconds / limit);
			fflush(stdout);
			if (seconds == limit)
				break;
		}
	}
	printf("\n\nSaving file...\n");
	for (i = 0; i < PATH_MAX; i++)
		if (fn[i] == 0)
			break;
	for (; i > 0; i--)
		if (fn[i] == '.')
			strcpy(&fn[i + 1], "it");
	if (ITWrite(fn))
		printf("Error: failed to write %s.\n", fn);
	else
		printf("Wrote to %s successfully.\n", fn);
	Reset_SPC();
	return 0;
}
