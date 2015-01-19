/****************************************************
*Part of SPC2IT, read readme.md for more information*
****************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "it.h"
#include "sound.h"
#include "emu.h"

itdata ITdata[8]; // Temp memory for patterns before going to file
u8 *ITpattbuf[NUM_PATT_BUFS]; // Where patterns are going to be , before writing to file
u8 *ITPatterns;
u32 ITPatternsSize;
s32 ITpattlen[NUM_PATT_BUFS]; // lengths of each pattern
s32 ITcurbuf, ITbufpos, ITcurrow; // Pointers into temp pattern buffers
s32 ITrows; // Number of rows per pattern

static s32 offset[IT_PATTERN_MAX]; // table of offsets into temp file to each pattern
static s32 curpatt; // which pattern we are on in temp file
static s32 curoffs; // where we are in file

static s32 ITPitchToNote(s32 pitch, s32 base)
{
	f64 tmp;
	s32 note;
	tmp = log2((f64)pitch / (f64)base) * 12 + 60;
	if (tmp > 127)
		tmp = 127;
	else if (tmp < 0)
		tmp = 0;
	note = (s32)tmp;
	if ((s32)(tmp * 2) != (note << 1))
		note++; // correct rounding
	return note;
}

static void ITWriteDSPCallback()
{
	s32 addr_lo = SPC_DSP_ADDR & 0xF;
	s32 addr_hi = SPC_DSP_ADDR >> 4;
	if (!(addr_lo == 12))
		return;

	if (!(addr_hi == 4))
		return;

	s32 i, cursamp, pitch;
	u8 v = SPC_DSP_DATA; // Ext
	v &= 0xFF; // ext
	for (i = 0; i < 8; i++)
	{
		if (v & (1 << i))
		{
			cursamp = SPC_DSP[4 + (i << 4)]; // Number of current sample
			if (cursamp < IT_SAMPLE_MAX) // Only 99 samples supported, sorry
			{
				pitch = (s32)(*(u16 *)&SPC_DSP[(i << 4) + 2]) << 3; // Ext, Get pitch
				if ((pitch != 0) && (SNDsamples[cursamp] != NULL) &&
				    (SNDsamples[cursamp]->freq != 0)) // Ext, Sample is actually useful?
				{
					ITdata[i].mask |= IT_MASK_NOTE_SAMPLE_ADJUSTVOLUME; // Update note, sample, and adjust the volume.
					ITdata[i].note = ITPitchToNote(pitch, SNDsamples[cursamp]->freq); // change pitch to note
					ITdata[i].pitch = (s32)(pow(2, ((f64)ITdata[i].note - 60) / 12) *
					                        (f64)SNDsamples[cursamp]->freq); // needed for pitch slide detection
					ITdata[i].lvol = 0;
					ITdata[i].rvol = 0;
					// IT code will get sample from DSP buffer
				}
			}
		}
	}
}

static void ITSSave(sndsamp *s, FILE *f) // Save sample
{
	s32 loopto = -1;
	s32 length = 0;
	s32 freq = 0;
	s32 ofs = ftell(f);
	ITFileSample *sHeader = calloc(1, sizeof(ITFileSample));
	if (sHeader == NULL)
	{
		printf("Error: could not allocate memory for ITFileSample struct\n");
		exit(1);
	}
	if (s != NULL)
	{
		loopto = s->loopto;
		length = s->length;
		freq = s->freq;
	}
	else
	{
		freq = 8363;
		loopto = 0;
	}
	memcpy(sHeader->magic, "IMPS", 4);
	if (length)
		strcpy(sHeader->fileName, "SPC2ITSAMPLE");
	sHeader->GlobalVolume = 64;
	sHeader->Flags |= 2; // Bit 1 (16 bit)
	if (length)
		sHeader->Flags |= 1; // Bit 0 (sample included with header)
	sHeader->Volume = 64;
	if (length)
		strcpy(sHeader->SampleName, "SPC2ITSAMPLE");
	sHeader->Convert = 1;
	sHeader->DefaultPan = 0;
	sHeader->NumberOfSamples = length;
	if (loopto != -1)
	{
		sHeader->Flags |= 16; // Bit 4 (Use loop)
		sHeader->LoopBeginning = loopto;
		sHeader->LoopEnd = length;
	}
	sHeader->C5Speed = freq;
	if (length)
		sHeader->SampleOffset = ofs + sizeof(ITFileSample);
	fwrite(sHeader, sizeof(ITFileSample), 1, f);
	free(sHeader);
	if (length)
		fwrite(s->buf, s->length * 2, 1, f); // Write the sample itself... 2x length.
}

static void ITWritePattern(ITPatternInfo *pInfo) {
	ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->Channel;
	ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->Mask;

	if (pInfo->Mask & IT_MASK_NOTE)
		ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->Note;
	if (pInfo->Mask & IT_MASK_SAMPLE)
		ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->Sample;
	if (pInfo->Mask & IT_MASK_ADJUSTVOLUME) 
		ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->Volume;
	if (pInfo->Mask & IT_MASK_PITCHSLIDE) 
	{
		ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->Command;
		ITpattbuf[ITcurbuf][ITbufpos++] = pInfo->CommandValue;
	}
}

s32 ITStart() // Opens up temporary file and inits writing
{
	SPCAddWriteDSPCallback(&ITWriteDSPCallback);
	s32 i;

	for (i = 0; i < NUM_PATT_BUFS; i++)
	{
		ITpattbuf[i] = calloc(1, Mem64k - 8); //Don't include the 8 byte header
		if (ITpattbuf[i] == NULL)
		{
			printf("Error: could not allocate memory for IT pattern buffer\n");
			exit(1);
		}
		ITpattlen[i] = 0;
	}

	ITPatterns = calloc(1, Mem64k * IT_PATTERN_MAX);
	if (ITPatterns == NULL)
	{
		printf("Error: could not allocate memory for IT pattern storage\n");
		exit(1);
	}
	ITPatternsSize = 0;
	ITcurbuf = 0;
	ITbufpos = 0;
	ITcurrow = 0;

	curoffs = 0;
	for (i = 0; i < IT_PATTERN_MAX; i++)
		offset[i] = -1; // -1 means unused pattern
	curpatt = 0;

	for (i = 0; i < 8; i++)
		ITdata[i].mask = 0;
	return 0;
}

s32 ITUpdate() // Dumps pattern buffers to file
{
	u8 *tmpptr;
	s32 i;
	ITFilePattern *pHeader = calloc(1, sizeof(ITFilePattern));
	if (pHeader == NULL)
	{
		printf("Error: could not allocate memory for ITFilePattern struct\n");
		exit(1);
	}
	for (i = 0; i < ITcurbuf; i++)
	{
		offset[curpatt] = curoffs;
		pHeader->Length = ITpattlen[i];
		pHeader->Rows = ITrows;
		memcpy(&ITPatterns[ITPatternsSize], pHeader, sizeof(ITFilePattern));
		ITPatternsSize += sizeof(ITFilePattern);
		memcpy(&ITPatterns[ITPatternsSize], ITpattbuf[i], ITpattlen[i]);
		ITPatternsSize += ITpattlen[i];
		curoffs += ITpattlen[i] + 8;
		if (curpatt < IT_PATTERN_MAX) 
			curpatt++; // Continue counting if we haven't reached the limit yet
	}
	free(pHeader);
	tmpptr = ITpattbuf[0];
	ITpattbuf[0] = ITpattbuf[ITcurbuf];
	ITpattbuf[ITcurbuf] = tmpptr;
	ITcurbuf = 0;
	return 0;
}

s32 ITWrite(char *fn) // Write the final IT file
{
	FILE *f;
	s32 i, t, numsamps, ofs;
	ITPatternInfo *pInfo = calloc(1, sizeof(ITPatternInfo));
	if (pInfo == NULL)
	{
		printf("Error: could not allocate memory for ITPatternInfo struct\n");
		exit(1);
	}
	// START IT CLEANUP
	if (fn == NULL)
	{
		printf("Error: no IT filename\n");
		exit(1);
	}
	pInfo->Mask = 1;
	pInfo->Note = 254; //note cut
	// Stop all notes and loop back to the beginning
	for (i = 0; i < 15; i++) // Save the last channel to put loop in
	{
		pInfo->Channel = (i + 1) | 128; // Channels are 1 based (Channels start at 1, not 0, ITTECH.TXT is WRONG) !!!
		ITWritePattern(pInfo);
	}
	pInfo->Channel = (15 + 1) | 128;
	pInfo->Mask = 9; // 1001 (note, special command)
	pInfo->Command = 2; // Effect B: jump to...
	pInfo->CommandValue = 0; //...order 0 (Loop to beginning)
	ITWritePattern(pInfo);
	free(pInfo);
	while (ITcurrow++ < ITrows)
		ITpattbuf[ITcurbuf][ITbufpos++] = 0; // end-of-row

	ITpattlen[ITcurbuf++] = ITbufpos;
	ITUpdate(); // Save the changes we just made
	// END IT CLEANUP
	f = fopen(fn, "wb");
	if (f == NULL)
	{
		printf("Error: could not open IT file\n");
		exit(1);
	}
	ITFileHeader *fHeader = calloc(1, sizeof(ITFileHeader));
	if (fHeader == NULL)
	{
		printf("Error: could not allocate memory for ITFileHeader struct\n");
		exit(1);
	}
	memcpy(fHeader->magic, "IMPM", 4);
	if (SPCInfo->SongTitle[0])
	{
		strncpy(fHeader->songName, SPCInfo->SongTitle, 25);
	}
	else
	{
		strcpy(fHeader->songName, "spc2it conversion"); // default string
	}
	fHeader->OrderNumber = curpatt + 1; // number of orders + terminating order
	for (numsamps = IT_SAMPLE_MAX + 1; SNDsamples[numsamps - 1] == NULL; numsamps--)
		; // Count the number of samples (the reason of the minus one is because c arrays start at 0)
	numsamps++;
	fHeader->SampleNumber = numsamps; // Number of samples
	fHeader->PatternNumber = curpatt; // Number of patterns
	fHeader->TrackerCreatorVersion = 0x214; // Created with this tracker version
	fHeader->TrackerFormatVersion = 0x200; // Compatible with this tracker version
	fHeader->Flags = 9; // Flags: Stereo, Linear Slides
	fHeader->GlobalVolume = 128; // Global volume
	fHeader->MixVolume = 100; // Mix volume
	fHeader->InitialSpeed = 1; // Initial speed (fastest)
	fHeader->InitialTempo = (u8)(SPCUpdateRate * 1.25); // Initial tempo (determined by update rate)
	fHeader->PanningSeperation = 128; // Stereo separation (max)
	for (i = 0; i < 8; i++)
	{ // Channel pan: Set 8 channels to left
		fHeader->ChannelPan[i] = 0;
	}
	for (i = 8; i < 16; i++)
	{ // Set 8 channels to right
		fHeader->ChannelPan[i] = 64;
	}
	for (i = 16; i < 64; i++)
	{ // Disable the rest of the channels (Value: +128)
		fHeader->ChannelPan[i] = 128;
	}
	for (i = 0; i < 16; i++)
	{ // Channel Vol: set 16 channels loud
		fHeader->ChannelVolume[i] = 64;
	}
	fwrite(fHeader, sizeof(ITFileHeader), 1, f);
	free(fHeader);
	// orders
	for (i = 0; i < curpatt; i++)
		fputc(i, f); // Write from 0 to the number of patterns (max: 0xFD)
	fputc(255, f); // terminating order
	// Sample offsets
	ofs = sizeof(ITFileHeader) + (curpatt + 1) + ((numsamps * sizeof(s32)) + (curpatt * sizeof(s32)));
	for (i = 0; i < numsamps; i++)
	{
		fwrite(&ofs, sizeof(s32), 1, f);
		ofs += sizeof(ITFileSample);
		if (SNDsamples[i] != NULL) // Sample is going to be put in file? Add the length of the sample.
			ofs += (SNDsamples[i]->length * 2);
	}
	// Pattern offsets
	for (i = 0; i < curpatt; i++)
	{
		t = offset[i] + ofs;
		fwrite(&t, sizeof(s32), 1, f);
	}
	// samples
	for (i = 0; i < numsamps; i++)
		ITSSave(SNDsamples[i], f);
	// patterns
	fwrite(ITPatterns, ITPatternsSize, 1, f);
	for (i = 0; i < NUM_PATT_BUFS; i++)
		free(ITpattbuf[i]);
	free(ITPatterns);
	fclose(f);
	return 0;
}

void ITMix()
{
	s32 envx, pitchslide, lvol = 0, rvol = 0, pitch, temp = 0, voice;
	ITPatternInfo *pInfo = calloc(1, sizeof(ITPatternInfo));
	if (pInfo == NULL)
	{
		printf("Error: could not allocate memory for ITPatternInfo struct\n");
		exit(1);
	}
	for (voice = 0; voice < 8; voice++)
	{
		if (IT_EXTERN_ISVOICEON(voice))
		{
			envx = IT_EXTERN_ENVX(voice);
			lvol = IT_EXTERN_VOL(envx, voice, 0); // Ext
			rvol = IT_EXTERN_VOL(envx, voice, 1); // Ext

			pitch = IT_EXTERN_PITCH(voice); // Ext

			// adjust for negative volumes
			if (lvol < 0)
				lvol = -lvol;
			if (rvol < 0)
				rvol = -rvol;
			// lets see if we need to pitch slide
			if (pitch && ITdata[voice].pitch)
			{
				pitchslide = (s32)(log2((f64)pitch / (f64)ITdata[voice].pitch) * 768);
				if (pitchslide)
					ITdata[voice].mask |= IT_MASK_PITCHSLIDE; // enable pitch slide
			}
			// adjust volume?
			if ((lvol != ITdata[voice].lvol) || (rvol != ITdata[voice].rvol))
			{
				ITdata[voice].mask |= IT_MASK_ADJUSTVOLUME; // Enable adjust volume
				ITdata[voice].lvol = lvol;
				ITdata[voice].rvol = rvol;
			}
		}

		pInfo->Channel = (voice + 1) | 128; //Channels here are 1 based!
		pInfo->Mask = ITdata[voice].mask;
		if (ITdata[voice].mask & IT_MASK_NOTE)
			pInfo->Note = ITdata[voice].note;
		if (ITdata[voice].mask & IT_MASK_SAMPLE)
			pInfo->Sample = IT_EXTERN_SAMPLE(voice);
		if (ITdata[voice].mask & IT_MASK_ADJUSTVOLUME)
			pInfo->Volume = (lvol > 64) ? 64 : lvol;
		if (ITdata[voice].mask & IT_MASK_PITCHSLIDE)
		{
			if (pitchslide > 0xF)
			{
				temp = pitchslide >> 2;
				if (temp > 0xF)
					temp = 0xF;
				temp |= FINE_SLIDE;
				ITdata[voice].pitch = (s32)((f64)ITdata[voice].pitch * pow(2, (f64)((temp & 0xF) << 2) / 768.0)); 
				pInfo->Command = EFFECT_F;
				pInfo->CommandValue = temp;
			}
			else if (pitchslide > 0)
			{
				temp = pitchslide | EXTRA_FINE_SLIDE;
				ITdata[voice].pitch = (s32)((f64)ITdata[voice].pitch * pow(2, (f64)(temp & 0xF) / 768.0));
				pInfo->Command = EFFECT_F;
				pInfo->CommandValue = temp;
			}
			else if (pitchslide > -0x10)
			{
				temp = (-pitchslide) | EXTRA_FINE_SLIDE;
				ITdata[voice].pitch = (s32)((f64)ITdata[voice].pitch * pow(2, (f64)(temp & 0xF) / -768.0));
				pInfo->Command = EFFECT_E;
				pInfo->CommandValue = temp;
			}
			else
			{
				temp = (-pitchslide) >> 2;
				if (temp > 0xF)
					temp = 0xF;
				temp |= FINE_SLIDE;
				ITdata[voice].pitch = (s32)((f64)ITdata[voice].pitch * pow(2, (f64)((temp & 0xF) << 2) / -768.0));
				pInfo->Command = EFFECT_E;
				pInfo->CommandValue = temp;
			}
		}
		ITWritePattern(pInfo); // Write for left channel
		pInfo->Channel = (voice + 8 + 1) | 128;
		if (ITdata[voice].mask & IT_MASK_ADJUSTVOLUME)
			pInfo->Volume = (rvol > 64) ? 64 : rvol;
		ITWritePattern(pInfo); // Write for right channel

		ITdata[voice].mask = 0; // Clear the mask 
	}
	ITpattbuf[ITcurbuf][ITbufpos++] = 0; // End-of-row
	if (++ITcurrow >= ITrows)
	{
		ITpattlen[ITcurbuf++] = ITbufpos;
		ITbufpos = 0; // Reset buffer pos
		ITcurrow = 0; // Reset current row
	}
	free(pInfo);
}
