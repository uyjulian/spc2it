cmake_minimum_required(VERSION 2.8)
project(spc2it)
set(spc2it_sources
	emu.c
	it.c
	main.c
	sound.c
	spc700.c
	emu.h
	it.h
	sneese_spc.h
	sound.h
	spc2ittypes.h
)

add_executable(spc2it ${spc2it_sources})
target_link_libraries(spc2it m)