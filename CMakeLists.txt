cmake_minimum_required(VERSION 2.8)
project(spc2it)
set(spc2it_sources
	spc700.c
	sneese_spc.h
)

add_library(spc2it MODULE ${spc2it_sources})
target_link_libraries(spc2it m)