cmake_minimum_required(VERSION 3.0...3.10)
project(spc2it)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

add_executable(spc2it
	emu.c
	it.c
	main.c
	sound.c
	spc700.c
)

set_target_properties(spc2it PROPERTIES C_STANDARD 11)

if(WIN32)
	target_link_options(spc2it PUBLIC -static -static-libgcc)
endif()
if((${CMAKE_SYSTEM_NAME} MATCHES "Linux") OR (${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD"))
	target_link_libraries(spc2it m)
endif()
