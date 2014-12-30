/****************************************************
*Part of SPC2IT, read readme.md for more information*
****************************************************/

#ifndef IT_H
#define IT_H

#define NUM_PATT_BUFS 64

#include "spc2ittypes.h"

extern s32 ITrows;

s32 ITStart(); // Opens temp file, inits writing
s32 ITUpdate(); // Dumps pattern buffers to file
s32 ITWrite(char *fn); // Stops recording and writes IT file from temp data
void ITMix();

// Macros

#define FINE_SLIDE 0xF0
#define EXTRA_FINE_SLIDE 0xE0
#define EFFECT_F 6
#define EFFECT_E 5

#define IT_PATTERN_TEMP_FILE_NAME "ittemp.tmp"
#define IT_PATTERN_MAX 200 // The original Impulse Tracker has 200 patterns max
#define IT_SAMPLE_MAX 99

#define IT_MASK_NOTE 1 // 0001 (Note)
#define IT_MASK_SAMPLE 2 // 0010 (Sample/instrument marker)
#define IT_MASK_ADJUSTVOLUME 4 // 0100 (volume/panning)
#define IT_MASK_NOTE_SAMPLE_ADJUSTVOLUME (IT_MASK_NOTE | IT_MASK_SAMPLE | IT_MASK_ADJUSTVOLUME)
#define IT_MASK_PITCHSLIDE 8 // 1000 (some special command, we use effect F and effect E)

#define IT_EXTERN_SAMPLE(v) (SPC_DSP[(v << 4) + 4] + 1)
#define IT_EXTERN_ENVX(v) (SNDDoEnv(v))
#define IT_EXTERN_VOL(e, v, o) ((((e >> 24) * (s32)((s8)SPC_DSP[(v << 4) + o]) * (s32)((s8)SPC_DSP[0x0C])) >> 14))
#define IT_EXTERN_ISVOICEON(v) (SNDkeys & (1 << v))
#define IT_EXTERN_PITCH(v) ((s32)(*(u16 *)&SPC_DSP[(v << 4) + 2]) << 3)

#endif