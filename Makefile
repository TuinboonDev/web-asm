build:
	nasm -f elf64 webserver.asm -o webserver.o
	ld webserver.o -o webserver -z noseparate-code --strip-all
	rm webserver.o

run: build
	./webserver

debug:
	nasm -f elf64 -g -F dwarf webserver.asm -o webserver.o
	ld webserver.o -o webserver
	rm webserver.o
	gdb webserver