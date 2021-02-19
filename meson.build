project(
	'spc2it',
	[
		'c',
	],
	default_options: [
		'optimization=3',
		'debug=true',
		'warning_level=1'
	],
	version: 'unknown'
)

spc2it_cflags = []

spc2it_ldflags = []
if target_machine.system() == 'windows'
	spc2it_ldflags += [
		'-static',
	]
endif

spc2it_src = [
	'emu.c',
	'it.c',
	'main.c',
	'sound.c',
	'spc700.c',
]

executable(
	'spc2it',
	sources: spc2it_src,
	c_args: spc2it_cflags,
	link_args: spc2it_ldflags,
)
