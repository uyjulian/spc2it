
ffi = require("ffi")
jit = require("jit")
bit = require("bit")

u8 = ffi.typeof("uint8_t")
s8 = ffi.typeof("int8_t")
u32 = ffi.typeof("uint32_t")
s32 = ffi.typeof("int32_t")

export IT_PATTERN_MAX = 0xFD
export IT_SAMPLE_MAX = 0xFF
export SPCUpdateRate = 100
export NUM_PATT_BUFS = 128
export IT_MASK_NOTE = 1
export IT_MASK_SAMPLE = 2
export IT_MASK_ADJUSTVOLUME = 4
export IT_MASK_NOTE_SAMPLE_ADJUSTVOLUME = bit.bor(IT_MASK_NOTE, IT_MASK_SAMPLE, IT_MASK_ADJUSTVOLUME)
export IT_MASK_PITCHSLIDE = 8
export OneKB = 1024
export Mem64k = OneKB * 64
export FINE_SLIDE = 0xF0
export EXTRA_FINE_SLIDE = 0xE0
export EFFECT_F = 6
export EFFECT_E = 5

ITpattbuf = ffi.new("u8*[?]", NUM_PATT_BUFS) -- Where patterns are going to be , before writing to file
ITPatterns = ""
ITpattlen = ffi.new("s32[?]", NUM_PATT_BUFS) -- lengths of each pattern

ITcurbuf = 0
ITbufpos = 0
ITcurrow = 0 -- Pointers into temp pattern buffers

ITrows = 0 -- Number of rows per pattern

offset = ffi.new("s32[?]", IT_PATTERN_MAX) -- table of offsets into temp file to each pattern
curpatt = 0 -- which pattern we are on in temp file
curoffs = 0 -- where we are in file

ITSamples = ffi.new("sndsamp*[?]", IT_SAMPLE_MAX)
ITdata = ffi.new("itdata[8]") -- Temp memory for patterns before going to file

SPCRAM = spc2itcore.SPCRAM
SPC_DSP = spc2itcore.SPC_DSP

log2 = (num) ->
	return math.log(num) / math.log(2)

ITWritePattern = (pInfo) ->
	
	ITpattbuf[ITcurbuf][ITbufpos] = pInfo.Channel
	ITbufpos = ITbufpos + 1
	
	ITpattbuf[ITcurbuf][ITbufpos] = pInfo.Mask
	ITbufpos = ITbufpos + 1
	if bit.band(pInfo.Mask, IT_MASK_NOTE) ~= 0
		ITpattbuf[ITcurbuf][ITbufpos] = pInfo.Note
		ITbufpos = ITbufpos + 1
	if bit.band(pInfo.Mask, IT_MASK_SAMPLE) ~= 0
		ITpattbuf[ITcurbuf][ITbufpos] = pInfo.Sample
		ITbufpos = ITbufpos + 1
	if bit.band(pInfo.Mask, IT_MASK_ADJUSTVOLUME) ~= 0
		ITpattbuf[ITcurbuf][ITbufpos] = pInfo.Volume
		ITbufpos = ITbufpos + 1
	if bit.band(pInfo.Mask, IT_MASK_PITCHSLIDE) ~= 0
		ITpattbuf[ITcurbuf][ITbufpos] = pInfo.Command
		ITbufpos = ITbufpos + 1
		ITpattbuf[ITcurbuf][ITbufpos] = pInfo.CommandValue
		ITbufpos = ITbufpos + 1

ITAllocateSample = (size) ->
	s = ffi.C.calloc(1, ffi.sizeof("sndsamp"))
	if s == nil
		return nil
	s = ffi.cast("sndsamp*", s)
	s.buf = ffi.C.calloc(1, size * 2)
	if s.buf == nil
		return nil
	s.length = size
	s.loopto = -1
	s.freq = 0
	return s

ITGetBRRPrediction = (filter, p1, p2) ->
	p = 0
	if filter == 0
		return 0
	elseif filter == 1
		p = p1
		p = p - bit.arshift(p1, 4)
		return p
	elseif filter == 2
		p = bit.lshift(p1, 1)
		p = p + bit.arshift((-(p1 + bit.lshift(p1, 1))), 5)
		p = p - p2
		p = p + bit.arshift(p2, 4)
		return p
	elseif filter == 3
		p = bit.lshift(p1, 1)
		p = p + bit.arshift((-(p1 + bit.lshift(p1, 2) + bit.lshift(p1, 3))), 6)
		p = p - p2
		p = p + bit.arshift((p2 + bit.lshift(p2, 1)), 4)
		return p
	return 0

p1 = 0
p2 = 0

ITDecodeSampleInternal = (s, shift_am, filter) ->
	a = 0
	if shift_am <= 0x0c --Valid shift count
		a = bit.arshift(bit.lshift(((s < 8) and s or (s - 16)), shift_am), 1)
	else
		a = (s < 8) and bit.lshift(1, 11) or bit.lshift((-1), 11) -- Values "invalid" shift counts

	a = a + ITGetBRRPrediction(filter, p1, p2)

	if a > 0x7fff
		a = 0x7fff
	elseif a < -0x8000
		a = -0x8000

	if a > 0x3fff
		a = a - 0x8000
	elseif a < -0x4000
		a = a + 0x8000

	p2 = p1
	p1 = a

ITDecodeSample = (start, sp) ->

	src = ffi.new("u8*", SPCRAM + start)
	edn = 0
	while bit.band(src[edn], 1) == 0 
		edn = edn + 9
	i = (edn + 9) / 9 * 16
	allsmp = ITAllocateSample(i)
	sp[0] = allsmp 
	s = allsmp
	if s == nil
		return 1
	if bit.band(src[edn], 2)
		s.loopto = 0
	brrptr = 0
	sampptr = 0
	while brrptr <= edn
		range = u8(src[brrptr])
		brrptr = brrptr + 1
		filter = u8(bit.arshift(bit.band(range, 0x0c), 2))
		shift_amount = u8(bit.band(bit.arshift(range, 4), 0x0F))
		i = 0
		while i < 8
			ITDecodeSampleInternal(bit.arshift(src[brrptr], 4), shift_amount, filter) -- Decode high nybble
			s.buf[sampptr] = 2 * p1
			sampptr = sampptr + 1
			ITDecodeSampleInternal(bit.band(src[brrptr], 0x0F), shift_amount, filter) -- Decode low nybble
			s.buf[sampptr] = 2 * p1
			sampptr = sampptr + 1
			i = i + 1
			brrptr = brrptr + 1
	return 0

ffi.cdef[[
	typedef struct
	{
		u16 vptr, lptr;
	} SRCDIRstruct;
]]

ITUpdateSample = (s) ->
	i = bit.lshift(SPC_DSP[0x5D], 8) --Sample directory table...
	SRCDIR = ffi.new("SRCDIRstruct*", ffi.cast("void*", SPCRAM + i))
	if ITDecodeSample(SRCDIR[s].vptr, ITSamples + s) ~= 0
		return
	if ITSamples[s].loopto ~= -1
		ITSamples[s].loopto = (SRCDIR[s].lptr - SRCDIR[s].vptr) / 9 * 16
		if (ITSamples[s].loopto > ITSamples[s].length) or (ITSamples[s].loopto < 0)
			ITSamples[s].loopto = -1

ITPitchToNote = (pitch, base) ->
	tmp = log2(tonumber(pitch) / tonumber(base)) * 12 + 60
	if (tmp > 127)
		tmp = 127
	elseif (tmp < 0)
		tmp = 0
	note = s32(tmp)
	if (s32(tmp * 2) ~= (note * 2))
		note = note + 1 -- round
	return note

export ITWriteDSPCallback = (v) ->
	addr_lo = bit.band(SPCRAM[0xF2], 0xF)
	addr_hi = bit.arshift(SPCRAM[0xF2], 4)
	if not (addr_lo == 12)
		return

	if not (addr_hi == 4)
		return

	local i
	local cursamp
	local pitch

	v = bit.band(v, 0xFF)
	for i = 0, 7
		if bit.band(v, bit.lshift(1, i)) ~= 0
			cursamp = SPC_DSP[4 + bit.lshift(i, 4)] -- Number of current sample
			if (cursamp < IT_SAMPLE_MAX) -- Only 99 samples supported, sorry
				if (ITSamples[cursamp] == nil)
					ITUpdateSample(cursamp)
				pitch = bit.bor(SPC_DSP[bit.lshift(i, 4) + 0x02], bit.lshift(SPC_DSP[bit.lshift(i, 4) + 0x03], 8)) * 7.8125 -- This code merges 2 numbers together, high and low 8 bits, to make 16 bits.
				if (ITSamples[cursamp].freq == 0)
					ITSamples[cursamp].freq = pitch
				if ((pitch ~= 0) and (ITSamples[cursamp] ~= nil) and (ITSamples[cursamp].freq ~= 0))
					ITdata[i].mask = bit.bor(ITdata[i].mask, IT_MASK_NOTE_SAMPLE_ADJUSTVOLUME) -- Update note, sample, and adjust the volume.
					ITdata[i].note = ITPitchToNote(pitch, ITSamples[cursamp].freq) -- change pitch to note
					ITdata[i].pitch = s32(math.pow(2, (tonumber(ITdata[i].note) - 60) / 12) * tonumber(ITSamples[cursamp].freq)) -- needed for pitch slide detection
					ITdata[i].lvol = 0
					ITdata[i].rvol = 0
					-- IT code will get sample from DSP buffer

export ITStart = (rows) ->
	ITrows = rows
	for i = 0, NUM_PATT_BUFS - 1
		ITpattbuf[i] = ffi.C.calloc(1, Mem64k - 8)
		if ITpattbuf[i] == nil
			io.stdout\write("Error: could not allocate memory for IT pattern buffer\n")
			os.exit(1)
		ITpattlen[i] = 0
	ITPatterns = ""

	ITcurbuf = 0
	ITbufpos = 0
	ITcurrow = 0

	curoffs = 0

	for i = 0, IT_PATTERN_MAX - 1
		offset[i] = -1

	curpatt = 0

	for i = 0, 7
		ITdata[i].mask = 0
	return 0

export ITUpdate = ->
	pHeader = ffi.C.calloc(1, ffi.sizeof("ITFilePattern"))
	if pHeader == nil
		io.stdout\write("Error: could not allocate memory for ITFilePattern struct\n")
		os.exit(1)
	pHeader = ffi.cast("ITFilePattern*", pHeader)
	for i = 0, ITcurbuf - 1
		offset[curpatt] = curoffs
		pHeader.Length = ITpattlen[i]
		pHeader.Rows = ITrows
		ITPatterns ..= ffi.string(pHeader, ffi.sizeof("ITFilePattern")) .. ffi.string(ITpattbuf[i], ITpattlen[i])

		curoffs = curoffs + ITpattlen[i] + 8
		if curpatt < IT_PATTERN_MAX
			curpatt = curpatt + 1
	ffi.C.free(pHeader)
	tmpptr = ffi.new("uint8_t*", ITpattbuf[0])
	ITpattbuf[0] = ITpattbuf[ITcurbuf]
	ITpattbuf[ITcurbuf] = tmpptr
	ITcurbuf = 0
	return 0

ITSSave = (s, f) ->
	loopto = -1
	length = 0
	freq = 0
	ofs = f\seek() --returns current file position
	sHeader = ffi.C.calloc(1, ffi.sizeof("ITFileSample"))
	if sHeader == nil
		io.stdout\write("Error: could not allocate memory for ITFileSample struct\n")
		os.exit(1)
	sHeader = ffi.cast("ITFileSample*", sHeader)
	if s ~= nil
		loopto = s.loopto
		length = s.length
		freq = s.freq
	else
		freq = 8363
		loopto = 0
	ffi.copy(sHeader.magic, "IMPS", 4)
	if length ~= 0
		ffi.copy(sHeader.fileName, "SPC2ITSAMPLE")
	sHeader.GlobalVolume = 64
	sHeader.Flags = bit.bor(sHeader.Flags, 2)
	if length ~= 0
		sHeader.Flags = bit.bor(sHeader.Flags, 1)
	sHeader.Volume = 64
	if length ~= 0
		ffi.copy(sHeader.SampleName, "SPC2ITSAMPLE")
	sHeader.Convert = 1
	sHeader.DefaultPan = 0
	sHeader.NumberOfSamples = length
	if loopto ~= -1
		sHeader.Flags = bit.bor(sHeader.Flags, 16)
		sHeader.LoopBeginning = loopto
		sHeader.LoopEnd = length
	sHeader.C5Speed = freq
	if length ~= 0
		sHeader.SampleOffset = ofs + ffi.sizeof("ITFileSample")
	f\write(ffi.string(sHeader, ffi.sizeof("ITFileSample")))
	ffi.C.free(sHeader)
	if length ~= 0
		f\write(ffi.string(s.buf, s.length * 2))

export ITWrite = (fn) ->
	pInfo = ffi.C.calloc(1, ffi.sizeof("ITPatternInfo"))
	if pInfo == nil
		io.stdout\write("Error: could not allocate memory for ITPatternInfo struct\n")
		os.exit(1)
	if fn == nil
		io.stdout\write("Error: no IT filename\n")
		os.exit(1)
	pInfo = ffi.cast("ITPatternInfo*", pInfo)
	pInfo.Mask = 1
	pInfo.Note = 254
	for i = 0, 14
		pInfo.Channel = bit.bor(i + 1, 128)
		ITWritePattern(pInfo)
	pInfo.Channel = bit.bor(15 + 1, 128)
	pInfo.Mask = 9
	pInfo.Command = 2
	pInfo.CommandValue = 0
	ITWritePattern(pInfo)
	ffi.C.free(pInfo)
	while ITcurrow < ITrows
		ITcurrow = ITcurrow + 1
		ITpattbuf[ITcurbuf][ITbufpos] = 0
		ITbufpos = ITbufpos + 1

	ITcurbuf = ITcurbuf + 1

	ITpattlen[ITcurbuf] = ITbufpos

	ITUpdate()

	f = io.open(fn, "wb")
	if f == nil
		io.stdout\write("Error: could not open IT file\n")
		os.exit(1)
	fHeader = ffi.C.calloc(1, ffi.sizeof("ITFileHeader"))
	if fHeader == nil
		io.stdout\write("Error: could not allocate memory for ITFileHeader struct\n")
		os.exit(1)
	fHeader = ffi.cast("ITFileHeader*", fHeader)
	ffi.copy(fHeader.magic, "IMPM", 4)
	if SPCInfo.SongTitle[0] ~= nil
		ffi.C.strncpy(fHeader.songName, ffi.string(SPCInfo.SongTitle), 26)
	else
		ffi.C.strcpy(fHeader.songName, "spc2it conversion")
	fHeader.OrderNumber = curpatt + 1
	numsamps = IT_SAMPLE_MAX
	while ITSamples[numsamps - 1] == nil
		numsamps = numsamps - 1

	numsamps = numsamps + 1

	fHeader.SampleNumber = numsamps
	fHeader.PatternNumber = curpatt
	fHeader.TrackerCreatorVersion = 0xDAEB
	fHeader.TrackerFormatVersion = 0x200
	fHeader.Flags = 9
	fHeader.GlobalVolume = 128
	fHeader.MixVolume = 100
	fHeader.InitialSpeed = 1
	fHeader.InitialTempo = math.floor(SPCUpdateRate * 2.5)
	fHeader.PanningSeperation = 128

	for i = 0, 7
		fHeader.ChannelPan[i] = 0
	for i = 8, 15
		fHeader.ChannelPan[i] = 64
	for i = 16, 63
		fHeader.ChannelPan[i] = 128
	for i = 0, 15
		fHeader.ChannelVolume[i] = 64
	f\write(ffi.string(fHeader, ffi.sizeof("ITFileHeader")))
	ffi.C.free(fHeader)
	for i = 0, curpatt - 1
		f\write(string.char(i))
	f\write(string.char(255))
	ofs = ffi.sizeof("ITFileHeader") + (curpatt + 1) + ((numsamps * ffi.sizeof("int32_t")) + (curpatt * ffi.sizeof("int32_t")))
	for i = 0, numsamps - 1
		f\write(ffi.string(ffi.new("int32_t[1]", s32(ofs)), 4))
		ofs = ofs + ffi.sizeof("ITFileSample")
		if ITSamples[i] ~= nil
			ofs = ofs + (ITSamples[i].length * 2)
	for i = 0, curpatt - 1
		t = ffi.new("int32_t[1]", s32(offset[i] + ofs))
		f\write(ffi.string(t, 4))
	for i = 1, numsamps
		ITSSave(ITSamples[i - 1], f)
	f\write(ITPatterns)
	for i = 0, NUM_PATT_BUFS - 1
		ffi.C.free(ITpattbuf[i])
	ITPatterns = ""
	f\close()
	return 0

export ITMix = ->
	lvol = s32(0)
	rvol = s32(0)
	local pitchslide
	local pitch
	local temp
	pInfo = ffi.C.calloc(1, ffi.sizeof("ITPatternInfo"))
	if pInfo == nil
		io.stdout\write("Error: could not allocate memory for ITPatternInfo struct\n")
		os.exit(1)
	pInfo = ffi.cast("ITPatternInfo*", pInfo)
	mastervolume = SPC_DSP[0x0C]
	for voice = 0, 7
		if bit.band(SPC_DSP[0x4C], bit.lshift(1, voice)) ~= 0 -- 0x4C == key on
			envx = SNDDoEnv(voice)

			-- This "cleaner" code is somehow broken.
			-- local lvolfloat = SPC_DSP[bit.lshift(voice, 4)       ] / 255
			-- local rvolfloat = SPC_DSP[bit.lshift(voice, 4) + 0x01] / 255
			-- local mastervolumefloat = SPC_DSP[0x0C] / 127
			-- local echofloat = SPC_DSP[0x2C] / 127
			-- local envxfloat = bit.arshift(envx, 24) / 
			-- lvol = lvolfloat * mastervolumefloat * envxfloat 
			-- rvol = rvolfloat * mastervolumefloat * envxfloat 


			--I don't know the logic of this code, hopefully somebody can drop in.

			lvol = bit.arshift(bit.arshift(envx, 24) * tonumber(s8(SPC_DSP[bit.lshift(voice, 4)       ])) * mastervolume, 14)
			rvol = bit.arshift(bit.arshift(envx, 24) * tonumber(s8(SPC_DSP[bit.lshift(voice, 4) + 0x01])) * mastervolume, 14)

			-- Volume no echo: (s32)((s8)SPC_DSP[(voice << 4)       ]) * mastervolume >> 7

			pitch = bit.bor(SPC_DSP[bit.lshift(voice, 4) + 0x02], bit.lshift(SPC_DSP[bit.lshift(voice, 4) + 0x03], 8)) * 7.8125 -- This code merges 2 numbers together, high and low 8 bits, to make 16 bits.

			-- adjust for negative volumes
			if lvol < 0
				lvol = -lvol
			if rvol < 0
				rvol = -rvol

			-- lets see if we need to pitch slide
			if (pitch ~= 0) and (ITdata[voice].pitch ~= 0)
				pitchslide = math.floor(log2(pitch / ITdata[voice].pitch) * 768)
				if pitchslide ~= 0
					ITdata[voice].mask = bit.bor(ITdata[voice].mask, IT_MASK_PITCHSLIDE) -- enable pitch slide

			-- adjust volume?
			if (lvol ~= ITdata[voice].lvol) or (rvol ~= ITdata[voice].rvol)
				ITdata[voice].mask = bit.bor(ITdata[voice].mask, IT_MASK_ADJUSTVOLUME) -- Enable adjust volume
				ITdata[voice].lvol = lvol
				ITdata[voice].rvol = rvol

		pInfo.Channel = bit.bor(voice + 1, 128) -- Channels here are 1 based!
		pInfo.Mask = ITdata[voice].mask
		if bit.band(ITdata[voice].mask, IT_MASK_NOTE) ~= 0
			pInfo.Note = ITdata[voice].note
		if bit.band(ITdata[voice].mask, IT_MASK_SAMPLE) ~= 0
			pInfo.Sample = SPC_DSP[bit.lshift(voice, 4) + 4] + 1
		if bit.band(ITdata[voice].mask, IT_MASK_ADJUSTVOLUME) ~= 0
			if lvol >= 64
				pInfo.Volume = 64
			else
				pInfo.Volume = lvol
		if bit.band(ITdata[voice].mask, IT_MASK_PITCHSLIDE) ~= 0
			if pitchslide > 0xF
				temp = bit.arshift(pitchslide, 2)
				if temp > 0xF
					temp = 0xF
				temp = bit.bor(temp, FINE_SLIDE)
				ITdata[voice].pitch = math.floor(ITdata[voice].pitch * math.pow(2, bit.lshift(bit.band(temp, 0xF), 2) / 768.0))
				pInfo.Command = EFFECT_F
				pInfo.CommandValue = temp
			elseif pitchslide > 0
				temp = bit.bor(pitchslide, EXTRA_FINE_SLIDE)
				ITdata[voice].pitch = math.floor(ITdata[voice].pitch * math.pow(2, bit.band(temp, 0xF) / 768.0))
				pInfo.Command = EFFECT_F
				pInfo.CommandValue = temp
			elseif pitchslide > -0x10
				temp = bit.bor(-pitchslide, EXTRA_FINE_SLIDE)
				ITdata[voice].pitch = math.floor(ITdata[voice].pitch * math.pow(2, bit.band(temp, 0xF) / -768.0))
				pInfo.Command = EFFECT_E
				pInfo.CommandValue = temp
			else
				temp = bit.arshift(-pitchslide, 2)
				if temp > 0xF
					temp = 0xF
				temp = bit.bor(temp, FINE_SLIDE)
				ITdata[voice].pitch = math.floor(ITdata[voice].pitch * math.pow(2, bit.lshift(bit.band(temp, 0xF), 2) / -768.0))
				pInfo.Command = EFFECT_E
				pInfo.CommandValue = temp
		ITWritePattern(pInfo) -- Write for left channel
		pInfo.Channel = bit.bor(voice + 8 + 1, 128)
		if bit.band(ITdata[voice].mask, IT_MASK_ADJUSTVOLUME) ~= 0
			if rvol >= 64
				pInfo.Volume = 64
			else
				pInfo.Volume = rvol
		ITWritePattern(pInfo) -- Write for right channel
		ITdata[voice].mask = 0 -- Clear the mask 
	ITpattbuf[ITcurbuf][ITbufpos] = 0 -- End-of-row
	ITbufpos = ITbufpos + 1
	ITcurrow = ITcurrow + 1
	if ITcurrow >= ITrows
		ITpattlen[ITcurbuf] = ITbufpos
		ITcurbuf = ITcurbuf + 1
		ITbufpos = 0 -- Reset buffer pos
		ITcurrow = 0 -- Reset current row

	ffi.C.free(pInfo)
