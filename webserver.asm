%define BACKLOG 10
%define PORT 0x901F
%define SA_RESTORER 0x04000000
%define AF_INET 2
%define SIGINT 2
%define BUFFER_LEN 2048
%define SOL_SOCKET 1
%define SO_REUSEADDR 2

section .data
    newline: db 10

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

    space_delimiter: db ' ', 0
    colon_delimiter: db ':', 0

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

    first_line: dq 0, 0, 0
    header: dq 0, 0


section .bss
    socket_fd: resq 1
    client_fd: resq 1
    buffer: resb BUFFER_LEN
    current_byte: resb 1
    reuse_addr: resd 1
    token_count: resq 1


section .text
	global _start


    ; TODO: specific registers to store temporary values
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

        ; TODO: move write
        ; Send (write) something to the client
        mov rax, 1
        mov rdi, [client_fd]
        lea rsi, [http_message]
        mov rdx, http_message_len
        xor r10, r10
        xor r8, r8
        xor r9, r9
        syscall

        test rax, rax
        js write_error

        ; TODO: move into read_firstline function
        ; ---

        ; TODO: add input into what buffer the data should be written
        ; Read a single line and check for any errors
        call read_line
        test rax, rax
        js read_error

        ; Move return value (amount of bytes read) into r12
        mov r12, rax

        ; Move pointers into register and split string
        mov rdi, buffer
        mov rsi, space_delimiter
        lea rdx, [first_line]
        mov r10, 3
        call split_string
        ; ---

        call read_headers

        ; ; Move array at index 1 to rdi
        ; mov rdi, [first_line + 1*8]
        ; call count_length

        ; ; Store the length of string at index 1 in r10
        ; mov r12, rax
        
        ; ; Print out the string at index 1
        ; mov rax, 1
        ; mov rdi, 1
        ; mov rsi, [first_line + 1*8]
        ; mov rdx, r12
		; syscall

        ; mov rax, 1
        ; mov rdi, 1
        ; mov rsi, newline
        ; mov rdx, 1
		; syscall

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

    read_headers:
        ; Read a single line and test for errors
        call read_line
        test rax, rax
        js read_error

        cmp rax, 2
        jle done

        ; Split the string at the colon
        mov rdi, buffer
        mov rsi, colon_delimiter
        lea rdx, [header]
        mov r10, 2
        call split_string

        ; Count the length of the header key
        mov rdi, [header + 0*8]
        call count_length

        ; Store the length of string at index 1 in r10
        mov r12, rax
        
        ; Print out the string at index 1
        mov rax, 1
        mov rdi, 1
        mov rsi, [header + 0*8]
        mov rdx, r12
		syscall

        mov rax, 1
        mov rdi, 1
        mov rsi, colon_delimiter
        mov rdx, 1
		syscall

        ; Count the length of header value
        mov rdi, [header + 1*8]
        call count_length

        ; Store the length of string at index 1 in r10
        mov r12, rax
        
        ; Print out the string at index 1
        mov rax, 1
        mov rdi, 1
        mov rsi, [header + 1*8]
        mov rdx, r12
		syscall

        mov rax, 1
        mov rdi, 1
        mov rsi, newline
        mov rdx, 1
		syscall

        jmp read_headers

    ; Counts the length of RDI and returns it into RAX
    count_length:
        xor rsi, rsi
    count_length_loop:
        mov rax, rsi

        cmp byte [rdi + rsi], 0
        je done

        inc rsi

        jmp count_length_loop

    done:
        ret

    split_string:
        xor r12, r12
    next_part:
        ; Stop at end of string
        cmp byte [rdi], 0
        je done

        ; Store input in array
        mov [rdx + r12*8], rdi
        inc r12

        cmp r12, r10
        je done

    find_delim:
        ; Stop at end of string
        cmp byte [rdi], 0
        je done
        
        ; Check if input pointer is equal to the delimiter
        mov al, [rdi]
        cmp al, [rsi]
        je split_here

        ; Increment the input pointer
        inc rdi
        jmp find_delim

    split_here:
        ; At delimiter set byte to 0
        mov byte [rdi], 0
        inc rdi
        jmp next_part

    read_line:
        xor r12, r12
    read_line_loop:
        ; Pointer into the buffer
        mov rax, 0
        mov rdi, [client_fd]
        lea rsi, [current_byte]
        mov rdx, 1
        syscall
        
        test rax, rax
        js return_error

        ; Check if the current byte is (\r)
        cmp byte [current_byte], 13
        je read_line_done

        ; Store the read byte into the buffer
        mov al, [current_byte]
        lea rbx, [buffer]
        add rbx, r12
        mov [rbx], al

        inc r12

        jmp read_line_loop

    read_line_done:
        ; Read one more bite (\n) and return the buffer in rax
        mov rax, 0
        mov rdi, [client_fd]
        lea rsi, [current_byte]
        mov rdx, 1
        syscall

        test rax, rax
        js return_error

        lea rbx, [buffer]
        add rbx, r12
        mov byte [rbx], 0

        inc r12

        mov rax, r12

        ret

    return_error:
        ; TODO: remove this mov because the syscall itself should store the right number in rax already
        mov rax, -1
        ret

    sigint_handler:
        ; Close the socket fd
        mov rax, 3
        mov rdi, [socket_fd]
        syscall

        ; TODO: test result of closing

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

        ret

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