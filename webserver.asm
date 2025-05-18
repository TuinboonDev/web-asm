%define BACKLOG 10
%define PORT 0x901F
%define SA_RESTORER 0x04000000
%define AF_INET 2
%define SIGINT 2
%define BUFFER_LEN 1024
%define SOL_SOCKET 1
%define SO_REUSEADDR 2

section .data
    socket_error_message: db 'Error while creating socket', 10
	socket_error_message_len: equ $-socket_error_message

    bind_error_message: db 'Error while binding socket', 10
	bind_error_message_len: equ $-bind_error_message

    listen_error_message: db 'Error while listening', 10
	listen_error_message_len: equ $-listen_error_message

    accept_error_message: db 'Error while accepting', 10
	accept_error_message_len: equ $-accept_error_message

    signal_error_message: db 'Error while creating signal', 10
	signal_error_message_len: equ $-signal_error_message

    write_error_message: db 'Error while writing', 10
	write_error_message_len: equ $-write_error_message

    close_error_message: db 'Error while closing', 10
	close_error_message_len: equ $-close_error_message

    shutdown_error_message: db 'Error while shutting down', 10
	shutdown_error_message_len: equ $-shutdown_error_message

    read_error_message: db 'Error while reading', 10
	read_error_message_len: equ $-read_error_message

    new_connection_message: db 'New Connection', 10
	new_connection_message_len: equ $-new_connection_message

    http_message: db 'HTTP/1.1 200 Ok', 13, 10, 'Connection: close', 13, 10, 'Content-Length: 14', 13, 10, 13, 10, 'New Connection'
	http_message_len: equ $-http_message

    exit_message: db 10, 'Successfully exitted', 10
	exit_message_len: equ $-exit_message

    debug_message: db 'Successfully debuged', 10
	debug_message_len: equ $-debug_message

    sockaddr:
        sin_family: dw 2
        sin_port: dw PORT
        sin_addr: dd 0
        sin_zero: times 8 db 0

    sigaction:
        sa_handler: dq sigint_handler
        sa_flags: dq SA_RESTORER
        sa_restorer: dq 0
        sa_mask: dq 0, 0

    reuse_addr: dd 1

section .bss
    socket_fd: resq 1
    client_fd: resq 1
    buffer: resb BUFFER_LEN

section .text
	global _start

	_start:
        ; Socket syscall
        mov rax, 41
        mov rdi, 2
        mov rsi, 1
        xor rdx, rdx
        syscall

        test rax, rax
        js socket_error

        ; Move FD into rbx
        mov [socket_fd], rax

        ; Set up a handler to close the socket on program exit
        mov rax, 13
        mov rdi, 2
        lea rsi, [sigaction]
        xor rdx, rdx
        mov r10, 8
        syscall

        test rax, rax
        js signal_error

        ; Setsockopt syscall to reuse previous address, prevents binding error
        mov rax, 54
        mov rdi, [socket_fd]
        mov rsi, SOL_SOCKET
        mov rdx, SO_REUSEADDR
        lea r10, [reuse_addr]
        mov r8, 4
        syscall

        ; Bind syscall
        mov rax, 49
        mov rdi, [socket_fd]
        lea rsi, [sockaddr]
        mov rdx, 16 
        syscall

        ; Check bind result
        test rax, rax
        js bind_error

        ; Listen syscall
        mov rax, 50
        mov rdi, [socket_fd]
        mov rsi, BACKLOG
        syscall

        ; Check listen result
        test rax, rax
        js listen_error

        ; Start accepting clients
        call accept_loop

        ; Probably redundant
        call exit

    accept_loop:
        ; Accept syscall
        mov rax, 43
        mov rdi, [socket_fd]
        xor rsi, rsi
        xor rdx, rdx
        syscall

        test rax, rax
        js accept_error

        ; Store stream fd
        mov [client_fd], rax

        ; Print out client address (soon)
        mov rax, 1
        mov rdi, 1
        mov rsi, new_connection_message
		mov rdx, new_connection_message_len
		syscall

        ; Send something to the client
        mov rax, 44
        mov rdi, [client_fd]
        lea rsi, [http_message]
        mov rdx, http_message_len
        xor r10, r10
        xor r8, r8
        xor r9, r9
        syscall

        test rax, rax
        js write_error

        ; Receive data
        mov rax, 45
        mov rdi, [client_fd]
        lea rsi, [buffer]
        mov rdx, BUFFER_LEN
        xor r10, r10
        xor r8, r8
        xor r9, r9
        syscall

        test rax, rax
        js read_error

        ; Store the amount of bytes read
        mov r12, rax

        ; Print out the full request
        mov rax, 1
        mov rdi, 1
        mov rsi, buffer
        mov rdx, r12
        syscall

        ; Shutdown syscall
        mov rax, 48
        mov rdi, [client_fd]
        mov rsi, 2
        syscall

        test rax, rax
        js shutdown_error
        
        ; Close client stream
        mov rax, 3
        mov rdi, [client_fd]
        syscall

        test rax, rax
        js close_error

        jmp accept_loop

    sigint_handler:
        mov rax, 3
        mov rdi, [socket_fd]
        syscall

        mov rax, 1
        mov rdi, 1
        mov rsi, exit_message
		mov rdx, exit_message_len
		syscall

        call exit

    debug:
        mov rax, 1
        mov rdi, 1
        mov rsi, debug_message
		mov rdx, debug_message_len
		syscall

        ret
    
    ; TODO: error functions in the client loop shouldnt exit
    read_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, read_error_message
		mov rdx, read_error_message_len
		syscall

    shutdown_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, shutdown_error_message
		mov rdx, shutdown_error_message_len
		syscall

        call exit

    close_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, close_error_message
		mov rdx, close_error_message_len
		syscall

        call exit
        
    write_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, write_error_message
		mov rdx, write_error_message_len
		syscall

        call exit

    signal_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, signal_error_message
		mov rdx, signal_error_message_len
		syscall

        call exit

    socket_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, socket_error_message
		mov rdx, socket_error_message_len
		syscall

        call exit

    bind_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, bind_error_message
		mov rdx, bind_error_message_len
		syscall

        call exit

    listen_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, listen_error_message
		mov rdx, listen_error_message_len
		syscall

        call exit

    accept_error:
        mov rax, 1
        mov rdi, 1
        mov rsi, accept_error_message
		mov rdx, accept_error_message_len
		syscall

        jmp accept_loop

    exit:
        mov rax, 60
        xor rdi, rdi
		syscall