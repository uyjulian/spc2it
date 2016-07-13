--SNDvoices = spc2itcore.SNDvoices
SPC_DSP = spc2itcore.SPC_DSP
active_context = spc2itcore.active_context

C = {[0]: 0x0, 0x20000, 0x18000, 0x14000, 0x10000, 0xC000, 0xA000, 0x8000, 0x6000, 0x5000, 0x4000, 0x3000, 0x2800, 0x2000, 0x1800, 0x1400, 0x1000, 0xC00, 0xA00, 0x800, 0x600, 0x500, 0x400, 0x300, 0x280, 0x200, 0x180, 0x140, 0x100, 0xC0, 0x80, 0x40} -- How many cycles till adjust ADSR/GAIN

ATTACK = 0 -- A of ADSR
DECAY = 1 -- D of ADSR
SUSTAIN = 2 -- S of ADSR
RELEASE = 3 -- R of ADSR
DECREASE = 4 -- GAIN linear decrease mode
EXP = 5 -- GAIN exponential decrease mode
INCREASE = 6 -- GAIN linear increase mode
BENT = 7 -- GAIN bent line increase mode
DIRECT = 8 -- Directly specify ENVX

ffi = require"ffi"

export SNDvoices = ffi.new("sndvoice[8]")



--export SNDDoEnv = spc2itcore.SNDDoEnv

export SNDDoEnv = (voice) ->
	currentvoice = SNDvoices[voice]
	envx = currentvoice.envx
	while true
		cyc = active_context.TotalCycles - currentvoice.envcyc
		switch currentvoice.envstate
			when ATTACK
				c = C[bit.lshift(currentvoice.ar, 1) + 1]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx += 0x2000000 -- add 1/64th
					if (envx >= 0x7F000000)
						envx = 0x7F000000
						if (currentvoice.sl ~= 7)
							currentvoice.envstate = DECAY
						else
							currentvoice.envstate = SUSTAIN
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when DECAY
				c = C[bit.lshift(currentvoice.dr, 1) + 0x10]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx = bit.rshift(envx, 8) * 255 -- mult by 1-1/256
					if (envx <= 0x10000000 * (currentvoice.sl + 1))
						envx = 0x10000000 * (currentvoice.sl + 1)
						currentvoice.envstate = SUSTAIN
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when SUSTAIN
				c = C[currentvoice.sr]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx = bit.rshift(envx, 8) * 255 -- mult by 1-1/256
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when RELEASE
				-- says add 1/256??  That won't release, must be subtract.
				-- But how often?  Oh well, who cares, I'll just
				-- pick a number. :)
				c = C[0x1A]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx -= 0x800000 -- sub 1/256th
					if ((envx == 0) or (envx > 0x7F000000))
						SPC_DSP[0x4C] = bit.band(SPC_DSP[0x4C], bit.bnot(bit.lshift(1, voice)))
						currentvoice.envx = 0
						return currentvoice.envx
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when INCREASE
				c = C[currentvoice.gn]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx += 0x2000000 -- add 1/64th
					if (envx > 0x7F000000)
						currentvoice.envcyc = active_context.TotalCycles
						currentvoice.envx = 0x7F000000
						return currentvoice.envx
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when DECREASE
				c = C[currentvoice.gn]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx -= 0x2000000     -- sub 1/64th
					if (envx > 0x7F000000) -- underflow
						currentvoice.envcyc = active_context.TotalCycles
						currentvoice.envx = 0
						return currentvoice.envx
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when EXP
				c = C[currentvoice.gn]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					envx = bit.rshift(envx, 8) * 255 -- mult by 1-1/256
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when BENT
				c = C[currentvoice.gn]
				if (c == 0)
					currentvoice.envcyc = active_context.TotalCycles
					currentvoice.envx = envx
					return currentvoice.envx
				if (cyc > c)
					currentvoice.envcyc += c
					if (envx < 0x60000000)
						envx += 0x2000000 -- add 1/64th
					else
						envx += 0x800000 -- add 1/256th
					if (envx > 0x7F000000)
						currentvoice.envcyc = active_context.TotalCycles
						currentvoice.envx = 0x7F000000
						return currentvoice.envx
				else
					currentvoice.envx = envx
					return currentvoice.envx
			when DIRECT
				currentvoice.envcyc = active_context.TotalCycles
				return envx

export SNDNoteOn = (v) ->
	v = bit.band(v, 0xFF)
	for i = 0, 7
		if bit.band(v, bit.lshift(1, (i))) ~= 0
			cursamp = SPC_DSP[4 + bit.lshift(i, 4)]
			if (cursamp < 512)
				SPC_DSP[0x4C] = bit.bor(SPC_DSP[0x4C], bit.lshift(1, i))
				-- figure ADSR/GAIN
				adsr1 = SPC_DSP[bit.lshift(i, 4) + 5]
				if bit.band(adsr1, 0x80) ~= 0
					-- ADSR mode
					adsr2 = SPC_DSP[bit.lshift(i, 4) + 6]
					SNDvoices[i].envx = 0
					SNDvoices[i].envcyc = active_context.TotalCycles
					SNDvoices[i].envstate = ATTACK
					SNDvoices[i].ar = bit.band(adsr1, 0xF)
					SNDvoices[i].dr = bit.band(bit.rshift(adsr1, 4), 7)
					SNDvoices[i].sr = bit.band(adsr2 , 0x1f)
					SNDvoices[i].sl = bit.rshift(adsr2, 5)
				else
					-- GAIN mode
					gain = SPC_DSP[bit.lshift(i, 4) + 7]
					if bit.band(gain, 0x80) ~= 0
						SNDvoices[i].envcyc = active_context.TotalCycles
						SNDvoices[i].envstate = bit.rshift(gain, 5)
						SNDvoices[i].gn = bit.band(gain, 0x1F)
					else
						SNDvoices[i].envx = bit.lshift(bit.band(gain, 0x7F), 24)
						SNDvoices[i].envstate = DIRECT
	ITWriteDSPCallback(v)

export SNDNoteOff = (v) ->
	for i = 0, 7
		if bit.band(v, bit.lshift(1, (i))) ~= 0
			SNDDoEnv(i)
			SNDvoices[i].envstate = RELEASE

export SNDInit = ->
	for i = 0, 7
		SNDvoices[i].envx = 0
	return 0
