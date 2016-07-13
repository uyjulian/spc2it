
ffi = require("ffi")
ffi.cdef[[

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef int8_t s8;
typedef int16_t s16;
typedef int32_t s32;
typedef int64_t s64;

void SPC_START(uint32_t cycles);
int32_t SNDratecnt;
uint8_t SPC_DSP[256];
uint8_t SPCRAM[65536];
uint32_t SPC_CPU_cycle_divisor;
uint32_t SPC_CPU_cycle_multiplicand;
uint32_t SPC_CPU_cycles_mul;
uint32_t SPC_DSP_DATA;
void spc_restore_flags();
void free(void *ptr);

typedef struct
{
	uint8_t PC[2]; //Don't turn this into u16, it will mess up the struct layout!
	uint8_t A;
	uint8_t X;
	uint8_t Y;
	uint8_t PSW;
	uint8_t SP;
	uint8_t Reserved[2];
} SPCFileRegisters;

typedef struct
{
	char SongTitle[32];
	char GameTitle[32];
	char DumperName[16];
	char Comment[32];
	char Date[11];
	char SongLength[3];
	char FadeLength[5];
	char Artist[32];
	uint8_t ChannelDisabled;
	uint8_t EmulatorDumpedWith; //0 unknown, 1 ZSNES, 2 Snes9x
	uint8_t Reserved[45]; 
} SPCFileInformation;
typedef struct
{
	char FileTag[33]; // SNES-SPC700 Sound File Data v0.30
	uint8_t FileTagTerminator[2]; // 0x1A, 0x1A
	uint8_t ContainsID666; // 0x1A for contains ID666, 0x1B for no ID666
	uint8_t Version; //Version minor (30)
	SPCFileRegisters Registers; // 9bytes
	SPCFileInformation Information; // 163bytes
	uint8_t RAM[65536];
	uint8_t DSPBuffer[128];
} SPCFile;
typedef struct
{
	uint16_t Length;
	uint16_t Rows;
	uint8_t Padding[4];
} ITFilePattern;

void Reset_SPC();
void* calloc(size_t count, size_t size);
typedef union
{
	uint16_t w;
	struct
	{
		uint8_t l;
		uint8_t h;
	} b;
} word_2b;
typedef struct
{
	uint8_t B_flag;
	uint8_t C_flag;
	uint8_t H_flag;
	uint8_t I_flag;
	uint8_t N_flag;
	uint8_t P_flag;
	uint8_t PSW;
	uint8_t SP;
	uint8_t V_flag;
	uint8_t X;
	uint8_t Z_flag;
	uint8_t cycle;
	uint8_t data;
	uint8_t data2;
	uint8_t opcode;
	uint8_t offset;

	word_2b PC;
	word_2b YA;
	word_2b address;
	word_2b address2;
	word_2b data16;
	word_2b direct_page;

	uint32_t Cycles;
	void *FFC0_Address;
	uint32_t TotalCycles;
	int32_t WorkCycles;
	uint32_t last_cycles;

	uint8_t PORT_R[4];
	uint8_t PORT_W[4];
	struct
	{
		uint8_t counter;
		int16_t position;
		int16_t target;
		uint32_t cycle_latch;
	} timers[4];
} SPC700_CONTEXT;
SPC700_CONTEXT *active_context;

typedef struct
{
	u8 Channel;
	u8 Mask;
	u8 Note;
	u8 Sample;
	u8 Volume;
	u8 Command;
	u8 CommandValue;
} ITPatternInfo;

typedef struct
{
	s32 mask, pitch, lvol, rvol;
	u8 note;
} itdata;

typedef struct
{
	s32 length;
	s32 loopto;
	s16 *buf;
	s32 freq;
} sndsamp;

typedef struct
{
	s32 ave;
	u32 envx, envcyc;
	s32 envstate;
	u32 ar, dr, sl, sr, gn;
} sndvoice;


typedef struct
{
	char magic[4]; // IMPM
	char songName[26];
	u16 PHiligt; // Pattern row hilight stuff
	u16 OrderNumber; // Number of orders in song
	u16 InstrumentNumber; // Number of instruments
	u16 SampleNumber; // Number of samples
	u16 PatternNumber; // Number of patterns
	u16 TrackerCreatorVersion; // The version of the tracker that created the IT file
	u16 TrackerFormatVersion; // Format version
	u16 Flags; // Information flags
	u16 Special; // Special st0ff
	u8 GlobalVolume; // Global volume
	u8 MixVolume; // Mix volume
	u8 InitialSpeed; // Initial speed
	u8 InitialTempo; // Initial tempo
	u8 PanningSeperation; // Panning separation between channels
	u8 PitchWheelDepth; // Pitch wheel depth for MIDI controllers
	u16 MessageLength; // Length of message if Bit 0 of Special is 1
	u32 MessageOffset; // Offset of message if Bit 0 of Special is 1
	u32 Reserved; // Reserved stuff
	u8 ChannelPan[64]; // Channel pan
	u8 ChannelVolume[64]; // Channel volume
} ITFileHeader;

typedef struct
{
	char magic[4]; // IMPS
	char fileName[13]; // 8.3 DOS filename (including null termating)
	u8 GlobalVolume; // Global volume for sample
	u8 Flags;
	u8 Volume; // Default volume
	char SampleName[26];
	u8 Convert;
	u8 DefaultPan;
	u32 NumberOfSamples; // not bytes! in samples!
	u32 LoopBeginning; // not bytes! in samples!
	u32 LoopEnd; // not bytes! in samples!
	u32 C5Speed; // Num of bytes a second for C-5
	u32 SustainLoopBeginning;
	u32 SustainLoopEnd;
	u32 SampleOffset; // the offset of the sample in file
	u8 VibratoSpeed;
	u8 VibratoDepth;
	u8 VibratoRate;
	u8 VibratoType;
} ITFileSample;

typedef struct
{
	u16 Length;
	u16 Rows;
	u8 Padding[4];
} ITFilePattern;

char * strcpy(char * dst, const char * src);
char * strncpy(char * dst, const char * src, size_t n);

s32 SNDDoEnv(s32);

void (*DisplaySPC)(void);
void (*InvalidSPCOpcode)(void);
void (*SPC_READ_DSP)(void);
void (*SPC_WRITE_DSP)(void);

sndvoice SNDvoices[8];
]]



export spc2itcore = ffi.load("ss/libspc2it.so")

moonscript = require"moonscript.base"

emumod, err = moonscript.loadfile("emu.moon")
if err
	print(err)
	os.exit(1)
else
	emumod()
itmod, err = moonscript.loadfile("it.moon")
if err
	print(err)
	os.exit(1)
else
	itmod()
soundmod, err = moonscript.loadfile("sound.moon")
if err
	print(err)
	os.exit(1)
else
	soundmod()

SPCUpdateRate = 100

fn = ""
limit = 0
ITrows = 200
realpath = (name) ->
	ss = io.popen("realpath \"" .. name .. "\"")
	lol = ss\read("*l")
	ss\close()
	return lol

for i, v in pairs(arg)
	if i >= 1
		if v\sub(1,1) == "-"
			option = v\sub(2,2)
			if option == "r"
				ITrows = tonumber(arg[i + 1]) or ITrows
			elseif option == "t"
				limit = tonumber(arg[i + 1]) or limit
			else
				print("warning: I don't recognize option -" .. option)
		else
			fn = realpath(v)

if fn == ""
	io.stdout\write("SPC2IT - converts SPC700 sound files to the Impulse Tracker format\n\n")
	io.stdout\write("Usage:  spc2it [options] <filename>\n")
	io.stdout\write("Where <filename> is any .spc or .sp# file\n\n")
	io.stdout\write("Options: \n")
	io.stdout\write("         -t x        Specify a time limit in seconds [60   default] \n")
	io.stdout\write("         -r xxx      Specify IT rows per pattern     [200  default] \n")
	os.exit(0)

io.stdout\write("\nFilepath: " .. fn .. "\n")

if ITStart(ITrows) == 1
	io.stdout\write("Error: failed to initialize pattern buffers\n")
	os.exit(1)

if SPCInit(fn) == 1
	io.stdout\write("Error: failed to initialize emulation\n")
	os.exit(1)

if SNDInit() == 1
	io.stdout\write("Error: failed to initialize sound\n")
	os.exit(1)

if (SPCtime ~= 0)
	limit = SPCtime
elseif (limit == 0)
	limit = 60

io.stdout\write("Time (seconds):      " .. limit .. "\n")

io.stdout\write("IT Parameters:\n")
io.stdout\write("    Rows/pattern:    " .. ITrows .. "\n")

io.stdout\write("ID info:\n")
io.stdout\write("        Song:  " .. ffi.string(SPCInfo.SongTitle) .. "\n")
io.stdout\write("        Game:  " .. ffi.string(SPCInfo.GameTitle) .. "\n")
io.stdout\write("      Dumper:  " .. ffi.string(SPCInfo.DumperName) .. "\n")
io.stdout\write("    Comments:  " .. ffi.string(SPCInfo.Comment) .. "\n")
io.stdout\write("  Created on:  " .. ffi.string(SPCInfo.Date) .. "\n")

io.stdout\write("\n")

io.stdout\flush()

SNDNoteOn(spc2itcore.SPC_DSP[0x4C])

seconds = 0
SNDratecnt = 0

while true
	ITMix()
	if ITUpdate() == 1
		break
	SNDratecnt = SNDratecnt + 1
	spc2itcore.SPC_START(2048000 / (SPCUpdateRate * 2)) -- emulate the SPC700 (2channel)
	if SNDratecnt >= SPCUpdateRate
		SNDratecnt = SNDratecnt - SPCUpdateRate
		seconds = seconds + 1
		io.stdout\write("Progress: " .. seconds / limit * 100 .. "%                 \r") --that spaces are so that the % sign doesn't get messed up
		io.stdout\flush()
		if seconds >= limit
			break

io.stdout\write("\n\nSaving file...\n")
outputFile = fn .. ".it"
if ITWrite(outputFile) == 1 then
	io.stdout\write("Error: failed to write " .. outputFile .. ".\n")
else
	io.stdout\write("Wrote to " .. outputFile .. " successfully.\n")

spc2itcore.Reset_SPC()

os.exit(0)
