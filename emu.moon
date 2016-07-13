
ffi = require("ffi")
bit = require("bit")

export SPCtime = 0

-- ID tag stuff
export SPCInfo = nil

u8 = ffi.typeof("uint8_t")
s32 = ffi.typeof("int32_t")

export LoadZState = (fn) ->
	sFile = ffi.C.calloc(1, ffi.sizeof("SPCFile"))
	if sFile == nil
		io.stdout\write("Error: could not allocate memory for SPCFile struct\n")
		os.exit(1)
	f = io.open(fn, "rb")
	if f == nil
		io.stdout\write("Error: can't open file\n")
		os.exit(1)
	f\seek("set", 0)
	str = f\read("*a")
	f\close()
	ffi.copy(sFile, str, #str)
	sFile = ffi.cast("SPCFile*", sFile )
	if ffi.string(sFile.FileTag, 27)\sub(1, 27) ~= "SNES-SPC700 Sound File Data"
		io.stdout\write("Error: invalid file format\n")
		os.exit(1)
	active_context = spc2itcore.active_context
	regs = sFile.Registers
	active_context.PC.w = bit.bor(bit.lshift(regs.PC[1], 8), regs.PC[0])
	active_context.YA.b.l = regs.A
	active_context.X = regs.X
	active_context.YA.b.h = regs.Y
	active_context.SP = 0x100 + regs.SP
	active_context.PSW = regs.PSW
	ffi.copy(spc2itcore.SPCRAM, sFile.RAM, 65536)
	ffi.copy(spc2itcore.SPC_DSP, sFile.DSPBuffer, 128)
	SPCInfo = ffi.C.calloc(1, ffi.sizeof("SPCFileInformation"))

	if SPCInfo == nil
		io.stdout\write("Error: could not allocate memory for SPCInfo struct\n")
		os.exit(1)
	SPCInfo = ffi.cast("SPCFileInformation*", SPCInfo )
	--spc2itcore.SPCInfo = SPCInfo
	ffi.copy(SPCInfo, sFile.Information, ffi.sizeof(sFile.Information)) --it.c is not rewritten yet
	SPCtime = tonumber(ffi.string(SPCInfo.SongLength, 3)) or 0
	if (bit.band(spc2itcore.SPCRAM[0xF1], 0x80)) == 0
		spc2itcore.active_context.FFC0_Address = spc2itcore.SPCRAM

	active_context.timers[0].target = u8(spc2itcore.SPCRAM[0xFA] - 1) + 1
	active_context.timers[1].target = u8(spc2itcore.SPCRAM[0xFB] - 1) + 1
	active_context.timers[2].target = u8(spc2itcore.SPCRAM[0xFC] - 1) + 1
	active_context.timers[0].counter = bit.band(spc2itcore.SPCRAM[0xFD] , 0xF)
	active_context.timers[1].counter = bit.band(spc2itcore.SPCRAM[0xFE] , 0xF)
	active_context.timers[2].counter = bit.band(spc2itcore.SPCRAM[0xFF] , 0xF)
	active_context.PORT_R[0] = spc2itcore.SPCRAM[0xF4]
	active_context.PORT_R[1] = spc2itcore.SPCRAM[0xF5]
	active_context.PORT_R[2] = spc2itcore.SPCRAM[0xF6]
	active_context.PORT_R[3] = spc2itcore.SPCRAM[0xF7]

	spc2itcore.SPC_CPU_cycle_multiplicand = 1
	spc2itcore.SPC_CPU_cycle_divisor = 1
	spc2itcore.SPC_CPU_cycles_mul = 0
	spc2itcore.spc_restore_flags()
	ffi.C.free(sFile)

export SPCInit = (fn) ->
	spc2itcore.Reset_SPC()
	if LoadZState(fn) == 1
		return 1
	return 0


spc2itcore.DisplaySPC = ->
	--do nothing

spc2itcore.InvalidSPCOpcode = ->
	io.stdout\write("Error: invalid SPC opcode\n")
	os.exit(1)

spc2itcore.SPC_READ_DSP = ->
	if bit.band(spc2itcore.SPCRAM[0xF2], 0xf) == 8 --ENVX
		spc2itcore.SPC_DSP[spc2itcore.SPCRAM[0xF2]] = bit.rshift(SNDDoEnv(bit.rshift(spc2itcore.SPCRAM[0xF2], 4)), 24)

spc2itcore.SPC_WRITE_DSP = ->
	addr_lo = s32(bit.band(spc2itcore.SPCRAM[0xF2], 0xF))
	addr_hi = s32(bit.rshift(spc2itcore.SPCRAM[0xF2], 4))
	switch addr_lo
		when 3 -- Pitch hi
			spc2itcore.SPC_DSP_DATA = bit.band(spc2itcore.SPC_DSP_DATA, 0x3F)
		when 5 -- ADSR1
			if (bit.band(spc2itcore.SPC_DSP[0x4C], bit.lshift(1, addr_hi)) and (bit.band(spc2itcore.SPC_DSP_DATA, 0x80) ~= bit.band(spc2itcore.SPC_DSP[spc2itcore.SPCRAM[0xF2]], 0x80)))
				local i
				-- First of all, in case anything was already
				-- going on, finish it up
				SNDDoEnv(addr_hi)
				if bit.band(spc2itcore.SPC_DSP_DATA, 0x80) ~= 0
					-- switch to ADSR--not sure what to do
					i = spc2itcore.SPC_DSP[bit.lshift(addr_hi, 4) + 6]
					SNDvoices[addr_hi].envstate = 0 --ATTACK
					SNDvoices[addr_hi].ar = bit.band(spc2itcore.SPC_DSP_DATA, 0xF)
					SNDvoices[addr_hi].dr = bit.band(bit.rshift(spc2itcore.SPC_DSP_DATA, 4), 7)
					SNDvoices[addr_hi].sr = bit.band(i, 0x1f)
					SNDvoices[addr_hi].sl = bit.rshift(i, 5)
				else
					-- switch to a GAIN mode
					i = spc2itcore.SPC_DSP[bit.lshift(addr_hi, 4) + 7]
					if bit.band(i, 0x80) ~= 0
						SNDvoices[addr_hi].envstate = bit.rshift(i, 5)
						SNDvoices[addr_hi].gn = bit.band(i, 0x1F)
					else
						SNDvoices[addr_hi].envx = bit.lshift(bit.band(i, 0x7F), 24)
						SNDvoices[addr_hi].envstate = 8 --DIRECT
		when 6 -- ADSR2
			-- Finish up what was going on
			SNDDoEnv(addr_hi)
			SNDvoices[addr_hi].sr = bit.band(spc2itcore.SPC_DSP_DATA, 0x1f)
			SNDvoices[addr_hi].sl = bit.rshift(spc2itcore.SPC_DSP_DATA, 5)
		when 7 -- GAIN
			if (bit.band(spc2itcore.SPC_DSP[0x4C], bit.lshift(1, addr_hi)) ~= 0 and (spc2itcore.SPC_DSP_DATA ~= spc2itcore.SPC_DSP[spc2itcore.SPCRAM[0xF2]]) and (bit.band(spc2itcore.SPC_DSP[bit.lshift(addr_hi, 4) + 5], 0x80) == 0))
				if bit.band(spc2itcore.SPC_DSP_DATA, 0x80) ~= 0
					-- Finish up what was going on
					SNDDoEnv(addr_hi)
					SNDvoices[addr_hi].envstate = bit.rshift(spc2itcore.SPC_DSP_DATA, 5)
					SNDvoices[addr_hi].gn = bit.band(spc2itcore.SPC_DSP_DATA, 0x1F)
				else
					SNDvoices[addr_hi].envx = bit.lshift(bit.band(spc2itcore.SPC_DSP_DATA, 0x7F), 24)
					SNDvoices[addr_hi].envstate = 8 --DIRECT
		-- These are general registers
		when 12 -- 0xc
			switch addr_hi
				when 4 -- Key on
					SNDNoteOn(spc2itcore.SPC_DSP_DATA)
					spc2itcore.SPC_DSP_DATA = spc2itcore.SPC_DSP[0x4C]
				when 5 -- Key off
					SNDNoteOff(spc2itcore.SPC_DSP_DATA)
					spc2itcore.SPC_DSP_DATA = 0

	spc2itcore.SPC_DSP[spc2itcore.SPCRAM[0xF2]] = spc2itcore.SPC_DSP_DATA

