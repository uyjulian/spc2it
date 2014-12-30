/****************************************************
*Part of SPC2IT, read readme.md for more information*
****************************************************/

#include <math.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

#include "emu.h"
#include "sound.h"
#include "it.h"

sndsamp *SNDsamples[100];
sndvoice SNDvoices[8];
s32 SNDkeys, SNDratecnt;

static const u32 C[0x20] = {
    0x0,    0x20000, 0x18000, 0x14000, 0x10000, 0xC000, 0xA000, 0x8000, 0x6000, 0x5000, 0x4000,
    0x3000, 0x2800,  0x2000,  0x1800,  0x1400,  0x1000, 0xC00,  0xA00,  0x800,  0x600,  0x500,
    0x400,  0x300,   0x280,   0x200,   0x180,   0x140,  0x100,  0xC0,   0x80,   0x40}; // How many cycles till adjust
                                                                                       // ADSR/GAIN

// PRIVATE (static) functions:

static sndsamp *NewSamp(s32 size)
{
	sndsamp *s;
	if (((s = malloc(sizeof(sndsamp))) == NULL) || ((s->buf = malloc(size * 2)) == NULL))
		return (NULL);
	s->length = size;
	s->loopto = -1;
	s->freq = 0;
	return (s);
}

static s32 decode_samp(u16 start, sndsamp **sp)
{
	sndsamp *s;
	u8 *src;
	u16 end;
	u32 brrptr, sampptr = 0;
	s32 i;
	s32 output;
	u8 range, filter;
	src = &SPCRAM[start];
	for (end = 0; !(src[end] & 1); end += 9)
		;
	i = (end + 9) / 9 * 16;
	*sp = s = NewSamp(i);
	if (s == NULL)
		return 1;
	if (src[end] & 2)
		s->loopto = 0;
	for (brrptr = 0; brrptr <= end;)
	{
		range = src[brrptr++];
		filter = (range & 12) >> 2;
		range >>= 4;
		for (i = 0; i < 8; i++, brrptr++)
		{
			output = (src[brrptr] >> 4) & 0x0F;
			if (output > 7)
				output |= 0xFFFFFFF0;
			output <<= range;
			if (filter == 1)
				output += (s32)((f64)s->buf[sampptr - 1] / 16 * 15);
			else if (filter == 2)
				output += (s32)(((f64)s->buf[sampptr - 1] * 61 / 32) - ((f64)s->buf[sampptr - 2] * 15 / 16));
			else if (filter == 3)
				output += (s32)(((f64)s->buf[sampptr - 1] * 115 / 64) - ((f64)s->buf[sampptr - 2] * 13 / 16));
			if (output > 32767)
				output = 32767;
			else if (output < -32768)
				output = -32768;
			s->buf[sampptr++] = output;
			output = src[brrptr] & 0x0F;
			if (output > 7)
				output |= 0xFFFFFFF0;
			output <<= range;
			if (filter == 1)
				output += (s32)((f64)s->buf[sampptr - 1] / 16 * 15);
			else if (filter == 2)
				output += (s32)(((f64)s->buf[sampptr - 1] * 61 / 32) - ((f64)s->buf[sampptr - 2] * 15 / 16));
			else if (filter == 3)
				output += (s32)(((f64)s->buf[sampptr - 1] * 115 / 64) - ((f64)s->buf[sampptr - 2] * 13 / 16));
			if (output > 32767)
				output = 32767;
			else if (output < -32768)
				output = -32768;
			s->buf[sampptr++] = output;
		}
	}
	return 0;
}

void update_samples(s32 s)
{
	s32 i;
	struct
	{
		u16 vptr, lptr;
	} *SRCDIR;
	i = SPC_DSP[0x5D] << 8;
	SRCDIR = (void *)&SPCRAM[i];
	if (decode_samp(SRCDIR[s].vptr, &SNDsamples[s]))
		return;
	if (SNDsamples[s]->loopto != -1)
	{
		SNDsamples[s]->loopto = (SRCDIR[s].lptr - SRCDIR[s].vptr) / 9 * 16;
		if ((SNDsamples[s]->loopto > SNDsamples[s]->length) || (SNDsamples[s]->loopto < 0))
			SNDsamples[s]->loopto = -1;
	}
}

// PUBLIC (non-static) functions:

s32 SNDDoEnv(s32 voice)
{
	u32 envx, cyc, c;
	envx = SNDvoices[voice].envx;
	for (;;)
	{
		cyc = TotalCycles - SNDvoices[voice].envcyc;
		switch (SNDvoices[voice].envstate)
		{
		case ATTACK:
			c = C[(SNDvoices[voice].ar << 1) + 1];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx += 0x2000000; // add 1/64th
				if (envx >= 0x7F000000)
				{
					envx = 0x7F000000;
					if (SNDvoices[voice].sl != 7)
						SNDvoices[voice].envstate = DECAY;
					else
						SNDvoices[voice].envstate = SUSTAIN;
				}
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case DECAY:
			c = C[(SNDvoices[voice].dr << 1) + 0x10];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx = (envx >> 8) * 255; // mult by 1-1/256
				if (envx <= 0x10000000 * (SNDvoices[voice].sl + 1))
				{
					envx = 0x10000000 * (SNDvoices[voice].sl + 1);
					SNDvoices[voice].envstate = SUSTAIN;
				}
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case SUSTAIN:
			c = C[SNDvoices[voice].sr];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx = (envx >> 8) * 255; // mult by 1-1/256
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case RELEASE:
			// says add 1/256??  That won't release, must be subtract.
			// But how often?  Oh well, who cares, I'll just
			// pick a number. :)
			c = C[0x1A];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx -= 0x800000; // sub 1/256th
				if ((envx == 0) || (envx > 0x7F000000))
				{
					SNDkeys &= ~(1 << voice);
					return SNDvoices[voice].envx = 0;
				}
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case INCREASE:
			c = C[SNDvoices[voice].gn];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx += 0x2000000; // add 1/64th
				if (envx > 0x7F000000)
				{
					SNDvoices[voice].envcyc = TotalCycles;
					return SNDvoices[voice].envx = 0x7F000000;
				}
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case DECREASE:
			c = C[SNDvoices[voice].gn];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx -= 0x2000000; // sub 1/64th
				if (envx > 0x7F000000) // underflow
				{
					SNDvoices[voice].envcyc = TotalCycles;
					return SNDvoices[voice].envx = 0;
				}
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case EXP:
			c = C[SNDvoices[voice].gn];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				envx = (envx >> 8) * 255; // mult by 1-1/256
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case BENT:
			c = C[SNDvoices[voice].gn];
			if (c == 0)
			{
				SNDvoices[voice].envcyc = TotalCycles;
				return SNDvoices[voice].envx = envx;
			}
			if (cyc > c)
			{
				SNDvoices[voice].envcyc += c;
				if (envx < 0x60000000)
					envx += 0x2000000; // add 1/64th
				else
					envx += 0x800000; // add 1/256th
				if (envx > 0x7F000000)
				{
					SNDvoices[voice].envcyc = TotalCycles;
					return SNDvoices[voice].envx = 0x7F000000;
				}
			}
			else
				return SNDvoices[voice].envx = envx;
			break;
		case DIRECT:
			SNDvoices[voice].envcyc = TotalCycles;
			return envx;
		}
	}
}

void SNDMix()
{
	SNDratecnt++;
	SPC_RUN(); // emulate the SPC700
}

void SNDNoteOn(u8 v)
{
	s32 i, cursamp, pitch, adsr1, adsr2, gain;
	v &= 0xFF;
	for (i = 0; i < 8; i++)
		if (v & (1 << i))
		{
			cursamp = SPC_DSP[4 + (i << 4)];
			if (cursamp <= 99) // Only 99 samples supported, sorry
			{
				if (SNDsamples[cursamp] == NULL)
					update_samples(cursamp);
				SNDvoices[i].cursamp = SNDsamples[cursamp];
				SNDvoices[i].sampptr = 0;
				SNDkeys |= (1 << i);
				pitch = (s32)(*(u16 *)&SPC_DSP[(i << 4) + 2]) << 3;
				if (SNDsamples[cursamp]->freq == 0)
					SNDsamples[cursamp]->freq = pitch;
				// figure ADSR/GAIN
				adsr1 = SPC_DSP[(i << 4) + 5];
				if (adsr1 & 0x80)
				{
					// ADSR mode
					adsr2 = SPC_DSP[(i << 4) + 6];
					SNDvoices[i].envx = 0;
					SNDvoices[i].envcyc = TotalCycles;
					SNDvoices[i].envstate = ATTACK;
					SNDvoices[i].ar = adsr1 & 0xF;
					SNDvoices[i].dr = adsr1 >> 4 & 7;
					SNDvoices[i].sr = adsr2 & 0x1f;
					SNDvoices[i].sl = adsr2 >> 5;
				}
				else
				{
					// GAIN mode
					gain = SPC_DSP[(i << 4) + 7];
					if (gain & 0x80)
					{
						SNDvoices[i].envcyc = TotalCycles;
						SNDvoices[i].envstate = gain >> 5;
						SNDvoices[i].gn = gain & 0x1F;
					}
					else
					{
						SNDvoices[i].envx = (gain & 0x7F) << 24;
						SNDvoices[i].envstate = DIRECT;
					}
				}
			}
		}
}

void SNDNoteOff(u8 v)
{
	s32 i;
	for (i = 0; i < 8; i++)
		if (v & (1 << i))
		{
			SNDDoEnv(i); // Finish up anything that was going on
			SNDvoices[i].envstate = RELEASE;
		}
}

s32 SNDInit()
{
	s32 i;
	SNDkeys = 0; // Which voices are keyed on (none)
	for (i = 0; i < 8; i++) // 8 voices
	{
		SNDvoices[i].sampptr = -1;
		SNDvoices[i].envx = 0;
	}
	return (0);
}
