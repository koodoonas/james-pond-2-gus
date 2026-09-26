; JP2GUS - clean-room native GF1 audio launcher for James Pond 2 (DOS)
;
; This program contains no game code or assets.  It validates one exact
; user-supplied release, patches three audio entry points in memory after the
; EXEPACK image expands, and leaves ROBOCOD.EXE unchanged on disk.
;
; Build: nasm -f bin -Wall -Werror -o JP2GUS.COM jp2gus.asm

bits 16
cpu 386
org 100h

%define TARGET_BYTES           82840
%define TARGET_CRC32           02FE69840h
%define MOD_HEADER_BYTES       1084
%define IO_BUFFER_BYTES        1024
%define SFX_BANK_BYTES         29342
%define SONG_COUNT             7
%define SAMPLES_PER_SONG       31
%define TOTAL_MUSIC_SAMPLES    217
%define GF1_VOICES             14
%define SELFTEST_TICKS         250
%define SELFTEST_BIOS_TICKS    128

%define PATCH_MUSIC_OFF        0CA8Ah
%define PATCH_STOP_OFF         0CAA3h
%define PATCH_SFX_OFF          0DE3Eh
%define UNPACK_RETURN_IP       0EAA4h
%define SOUND_SEG_DELTA        01EC5h

%define SFX_SCRIPT_TABLE       053F8h
%define SFX_DESCRIPTOR_TABLE   05334h
%define SFX_NOTE_LOW_TABLE     04C88h
%define SFX_NOTE_HIGH_TABLE    04D4Ah

    jmp start

; ---------------------------------------------------------------------------
; Startup and parent process

start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    sti
    mov ds, ax
    mov es, ax
    cld
    mov [psp_segment], ax

    mov dx, msg_banner
    call print_dos
    call parse_command_line
    jc fatal_args
    call show_settings
    call validate_target
    jc fatal_target
    call parse_ultrasnd
    jc fatal_config
    call setup_gus_ports
    call gus_reset
    call gus_probe_1mb
    jc fatal_gus
    call gus_set_interface

    mov dword [dram_cursor], 0
    call load_sfx_bank
    jc fatal_assets
    call load_all_modules
    jc fatal_assets
    call make_test_sample

    ; All temporary file buffers are above resident_end.  Return them and the
    ; unused DOS allocation before starting the child.
    mov bx, RESIDENT_PARAS
    mov ah, 4Ah
    int 21h
    jc fatal_memory

    call install_vectors
    call gus_timer_start
    cmp byte [run_mode], 1
    je run_selftest

    call exec_game
    mov [exec_error], ax
    mov byte [exec_failed], 0
    jnc .child_done
    mov byte [exec_failed], 1
    jmp .cleanup
.child_done:
    mov ah, 4Dh
    int 21h
    mov [child_exit_code], al
.cleanup:
    push cs
    pop ds
    call cleanup

    cmp byte [exec_failed], 0
    jne report_exec_failure
    cmp byte [patch_installed], 1
    jne report_patch_failure
    mov dx, msg_run_ok
    call print_dos
    cmp byte [run_mode], 2
    jb .no_counts
    call report_counters
.no_counts:
    mov al, [child_exit_code]
    jmp exit_dos

report_exec_failure:
    mov dx, msg_exec_failed
    call print_dos
    mov ax, [exec_error]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, 1
    jmp exit_dos

report_patch_failure:
    mov dx, msg_patch_missing
    call print_dos
    mov al, 2
    jmp exit_dos

run_selftest:
    mov dx, msg_test_start
    call print_dos
    xor ax, ax
    call select_song
    call play_test_sample
    xor ax, ax
    mov es, ax
    mov ax, [es:046Ch]
    mov [bios_tick_start], ax
.wait:
    cmp word [total_ticks], SELFTEST_TICKS
    jae .passed
    mov ax, [es:046Ch]
    sub ax, [bios_tick_start]
    cmp ax, SELFTEST_BIOS_TICKS
    jae .failed
    mov ah, 01h
    int 16h
    jnz .key
    sti
    hlt
    jmp .wait
.key:
    mov ah, 00h
    int 16h
    cmp word [total_ticks], 0
    je .failed
.passed:
    push cs
    pop ds
    call cleanup
    mov dx, msg_test_ok
    call print_dos
    call report_counters
    xor al, al
    jmp exit_dos
.failed:
    push cs
    pop ds
    call cleanup
    mov dx, msg_test_failed
    call print_dos
    mov al, 3
    jmp exit_dos

fatal_args:
    mov dx, msg_bad_args
    jmp fatal_plain
fatal_target:
    mov dx, msg_bad_target
    jmp fatal_plain
fatal_config:
    mov dx, msg_bad_config
    jmp fatal_plain
fatal_memory:
    mov dx, msg_no_memory
    jmp fatal_quiet
fatal_gus:
    mov dx, msg_no_gus
    jmp fatal_quiet
fatal_assets:
    mov dx, msg_bad_assets
fatal_quiet:
    push dx
    call gus_quiet
    call gus_restore_interface
    pop dx
fatal_plain:
    call print_dos
    mov al, 1
exit_dos:
    mov ah, 4Ch
    int 21h

print_dos:
    mov ah, 09h
    int 21h
    ret

print_hex_word:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 0Fh
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret

report_counters:
    mov dx, msg_counts
    call print_dos
    mov ax, [songs_started]
    call print_hex_word
    mov dx, msg_count_sfx
    call print_dos
    mov ax, [sfx_notes]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    ret

print_decimal_byte:
    push ax
    push bx
    push dx
    cmp al, 100
    jne .tens
    mov dl, '1'
    mov ah, 02h
    int 21h
    mov dl, '0'
    int 21h
    int 21h
    jmp .done
.tens:
    xor ah, ah
    mov bl, 10
    div bl
    mov bh, ah
    or al, al
    jz .ones
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
.ones:
    mov dl, bh
    add dl, '0'
    mov ah, 02h
    int 21h
.done:
    pop dx
    pop bx
    pop ax
    ret

show_settings:
    mov dx, msg_settings_joy
    call print_dos
    mov dx, msg_off
    cmp byte [joystick_enabled], 0
    je .joy
    mov dx, msg_on
.joy:
    call print_dos
    mov dx, msg_settings_music
    call print_dos
    mov al, [music_percent]
    call print_decimal_byte
    mov dx, msg_settings_sfx
    call print_dos
    mov al, [sfx_percent]
    call print_decimal_byte
    mov dx, msg_settings_pan
    call print_dos
    mov dl, '+'
    cmp byte [pan_reverse], 0
    je .pan_sign
    mov dl, '-'
.pan_sign:
    mov ah, 02h
    int 21h
    mov al, [pan_percent]
    call print_decimal_byte
    mov dx, msg_percent_crlf
    call print_dos
    ret

; /T performs a hardware self-test. /I runs normally and prints event counters
; after the game exits. /X is reserved for the automated integration harness.
parse_command_line:
    mov byte [run_mode], 0
    mov byte [joystick_enabled], 1
    mov byte [pan_percent], 60
    mov byte [pan_reverse], 0
    mov byte [music_percent], 75
    mov byte [sfx_percent], 81
    xor cx, cx
    mov cl, [80h]
    mov si, 81h
.space:
    or cx, cx
    jz .ok
    mov al, [si]
    inc si
    dec cx
    cmp al, ' '
    je .space
    cmp al, 9
    je .space
    cmp al, '/'
    je .switch
    cmp al, '-'
    jne .bad
.switch:
    or cx, cx
    jz .bad
    mov al, [si]
    inc si
    dec cx
    and al, 0DFh
    cmp al, 'T'
    je .test
    cmp al, 'I'
    je .integration
    cmp al, 'X'
    je .automated
    cmp al, 'J'
    je .joystick
    cmp al, 'N'
    je .no_joystick
    cmp al, 'P'
    je .pan
    cmp al, 'M'
    je .music
    cmp al, 'S'
    je .sfx
    jmp .bad
.test:
    cmp byte [run_mode], 0
    jne .bad
    mov byte [run_mode], 1
    jmp .token_end
.integration:
    cmp byte [run_mode], 0
    jne .bad
    mov byte [run_mode], 2
    jmp .token_end
.automated:
    cmp byte [run_mode], 0
    jne .bad
    mov byte [run_mode], 3
    jmp .token_end
.joystick:
    mov byte [joystick_enabled], 1
    jmp .token_end
.no_joystick:
    jcxz .bad
    mov al, [si]
    inc si
    dec cx
    and al, 0DFh
    cmp al, 'J'
    jne .bad
    mov byte [joystick_enabled], 0
    jmp .token_end
.pan:
    call skip_value_separator
    jcxz .bad
    mov byte [pan_reverse], 0
    mov al, [si]
    cmp al, '-'
    jne .pan_plus
    mov byte [pan_reverse], 1
    inc si
    dec cx
    jmp .pan_value
.pan_plus:
    cmp al, '+'
    jne .pan_value
    inc si
    dec cx
.pan_value:
    call parse_percent_digits
    jc .bad
    mov [pan_percent], bl
    jmp .token_end
.music:
    call skip_value_separator
    call parse_percent_digits
    jc .bad
    mov [music_percent], bl
    jmp .token_end
.sfx:
    call skip_value_separator
    call parse_percent_digits
    jc .bad
    mov [sfx_percent], bl
.token_end:
    jcxz .ok
    mov al, [si]
    cmp al, ' '
    je .space
    cmp al, 9
    je .space
.bad:
    stc
    ret
.ok:
    call set_music_pan
    call set_master_levels
    call build_exec_tail
    clc
    ret

skip_value_separator:
    jcxz .done
    mov al, [si]
    cmp al, '='
    je .skip
    cmp al, ':'
    jne .done
.skip:
    inc si
    dec cx
.done:
    ret

; Parse an unsigned decimal integer in the range 0..100.  SI/CX advance to
; the first non-digit and BX receives the result.
parse_percent_digits:
    push ax
    push dx
    push di
    xor bx, bx
    xor di, di
.digit:
    jcxz .end
    mov al, [si]
    cmp al, '0'
    jb .end
    cmp al, '9'
    ja .end
    sub al, '0'
    xor ah, ah
    mov dx, ax
    imul bx, bx, 10
    add bx, dx
    cmp bx, 100
    ja .bad
    inc si
    dec cx
    inc di
    jmp .digit
.end:
    or di, di
    jz .bad
    pop di
    pop dx
    pop ax
    clc
    ret
.bad:
    pop di
    pop dx
    pop ax
    stc
    ret

; Convert the user-facing 0..100 percentages to the mixer's 0..64 scale.
set_master_levels:
    mov al, [music_percent]
    call percent_to_master
    mov [music_master], al
    mov al, [sfx_percent]
    call percent_to_master
    mov [sfx_master], al
    ret

percent_to_master:
    push bx
    xor ah, ah
    mov bl, 64
    mul bl
    add ax, 50
    mov bl, 100
    div bl
    pop bx
    ret

; Pan width 0 is centered, 100 is full LRRL separation, and a negative sign
; reverses left and right.  The default 60 recreates the original 3/12 split.
set_music_pan:
    cmp byte [pan_percent], 0
    jne .width
    mov bl, 7
    mov bh, 7
    jmp .orient
.width:
    xor ah, ah
    mov al, 100
    sub al, [pan_percent]
    mov bl, 15
    mul bl
    add ax, 100
    mov bx, 200
    xor dx, dx
    div bx
    mov bl, al
    mov bh, 15
    sub bh, bl
.orient:
    cmp byte [pan_reverse], 0
    je .store
    xchg bl, bh
.store:
    mov [music_pan], bl
    mov [music_pan+1], bh
    mov [music_pan+2], bh
    mov [music_pan+3], bl
    ret

build_exec_tail:
    cmp byte [joystick_enabled], 0
    je .off
    mov byte [exec_tail], 3
    mov byte [exec_tail+1], ' '
    mov byte [exec_tail+2], '+'
    mov byte [exec_tail+3], 'J'
    mov byte [exec_tail+4], 13
    ret
.off:
    mov byte [exec_tail], 0
    mov byte [exec_tail+1], 13
    ret

; ---------------------------------------------------------------------------
; Exact-release validation.  A bit-at-a-time CRC costs nothing during play and
; avoids carrying a 1 KiB table in conventional memory.

validate_target:
    mov dx, game_filename
    mov ax, 3D00h
    int 21h
    jc .fail
    mov [file_handle], ax
    mov bx, ax
    mov dword [file_count], 0
    mov dword [file_crc], 0FFFFFFFFh
.read:
    mov dx, io_buffer
    mov cx, IO_BUFFER_BYTES
    mov ah, 3Fh
    int 21h
    jc .close_fail
    or ax, ax
    jz .eof
    movzx eax, ax
    add dword [file_count], eax
    mov cx, ax
    mov si, io_buffer
    mov edx, [file_crc]
.byte:
    movzx eax, byte [si]
    inc si
    xor edx, eax
    mov di, 8
.bit:
    shr edx, 1
    jnc .next_bit
    xor edx, 0EDB88320h
.next_bit:
    dec di
    jnz .bit
    loop .byte
    mov [file_crc], edx
    jmp .read
.eof:
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
    not dword [file_crc]
    cmp dword [file_count], TARGET_BYTES
    jne .fail
    cmp dword [file_crc], TARGET_CRC32
    jne .fail
    clc
    ret
.close_fail:
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
; ULTRASND=base,dma1,dma2,irq1,irq2

parse_ultrasnd:
    push es
    mov ax, [2Ch]
    or ax, ax
    jz .fail
    mov es, ax
    xor di, di
.next:
    cmp byte [es:di], 0
    jne .compare
    cmp byte [es:di+1], 0
    je .fail
    inc di
    jmp .next
.compare:
    push di
    mov si, ultrasnd_key
    mov cx, 9
.char:
    mov al, [es:di]
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    ja .upper
    sub al, 20h
.upper:
    cmp al, [si]
    jne .not_this
    inc di
    inc si
    loop .char
    pop bx
    call parse_hex
    jc .fail
    mov [gus_base], ax
    call comma
    jc .fail
    call parse_decimal
    jc .fail
    mov [gus_dma1], ax
    call comma
    jc .fail
    call parse_decimal
    jc .fail
    mov [gus_dma2], ax
    call comma
    jc .fail
    call parse_decimal
    jc .fail
    mov [gus_irq], ax
    call comma
    jc .fail
    call parse_decimal
    jc .fail
    mov [gus_midi_irq], ax
    cmp byte [es:di], 0
    jne .fail

    mov ax, [gus_base]
    cmp ax, 210h
    jb .fail
    cmp ax, 260h
    ja .fail
    test al, 0Fh
    jnz .fail
    mov bx, [gus_dma1]
    cmp bx, 7
    ja .fail
    cmp byte [dma_lut+bx], 0
    je .fail
    mov bx, [gus_dma2]
    cmp bx, 7
    ja .fail
    cmp byte [dma_lut+bx], 0
    je .fail
    mov bx, [gus_irq]
    cmp bx, 15
    ja .fail
    cmp byte [irq_lut+bx], 0
    je .fail
    mov bx, [gus_midi_irq]
    cmp bx, 15
    ja .fail
    cmp byte [irq_lut+bx], 0
    je .fail
    pop es
    clc
    ret
.not_this:
    pop di
.skip:
    cmp byte [es:di], 0
    je .past
    inc di
    jmp .skip
.past:
    inc di
    jmp .next
.fail:
    pop es
    stc
    ret

comma:
    cmp byte [es:di], ','
    jne .bad
    inc di
    clc
    ret
.bad:
    stc
    ret

parse_hex:
    xor bx, bx
    xor cx, cx
.loop:
    mov al, [es:di]
    cmp al, ','
    je .done
    or al, al
    jz .done
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .number
    and al, 0DFh
    cmp al, 'A'
    jb .bad
    cmp al, 'F'
    ja .bad
    sub al, 'A'-10
    jmp .add
.number:
    sub al, '0'
.add:
    shl bx, 4
    xor ah, ah
    add bx, ax
    inc di
    inc cx
    jmp .loop
.done:
    jcxz .bad
    mov ax, bx
    clc
    ret
.bad:
    stc
    ret

parse_decimal:
    xor bx, bx
    xor cx, cx
.loop:
    mov al, [es:di]
    cmp al, ','
    je .done
    or al, al
    jz .done
    cmp al, '0'
    jb .bad
    cmp al, '9'
    ja .bad
    sub al, '0'
    mov dl, al
    mov ax, bx
    shl bx, 1
    shl ax, 3
    add bx, ax
    xor dh, dh
    add bx, dx
    inc di
    inc cx
    jmp .loop
.done:
    jcxz .bad
    mov ax, bx
    clc
    ret
.bad:
    stc
    ret

; ---------------------------------------------------------------------------
; GF1 low-level setup and DRAM access

setup_gus_ports:
    mov ax, [gus_base]
    mov dx, ax
    add dx, 102h
    mov [gus_voice_port], dx
    inc dx
    mov [gus_command_port], dx
    inc dx
    mov [gus_data_low_port], dx
    inc dx
    mov [gus_data_high_port], dx
    mov dx, ax
    add dx, 006h
    mov [gus_status_port], dx
    add dx, 2
    mov [gus_timer_control_port], dx
    inc dx
    mov [gus_timer_data_port], dx
    mov dx, ax
    add dx, 107h
    mov [gus_dram_port], dx
    ret

gus_set_interface:
    pushf
    cli
    xor cx, cx
    mov bx, [gus_irq]
    mov cl, [irq_lut+bx]
    mov bx, [gus_midi_irq]
    mov al, [irq_lut+bx]
    shl al, 3
    or cl, al
    mov ax, [gus_irq]
    cmp ax, [gus_midi_irq]
    jne .irq_ready
    or cl, 40h
.irq_ready:
    mov [irq_latch], cl
    xor cx, cx
    mov bx, [gus_dma1]
    mov cl, [dma_lut+bx]
    mov bx, [gus_dma2]
    mov al, [dma_lut+bx]
    shl al, 3
    or cl, al
    mov ax, [gus_dma1]
    cmp ax, [gus_dma2]
    jne .dma_ready
    or cl, 40h
.dma_ready:
    mov [dma_latch], cl

    mov dx, [gus_base]
    add dx, 0Fh
    mov al, 05h
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    xor al, al
    out dx, al
    mov dx, [gus_base]
    add dx, 0Fh
    xor al, al
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    mov al, [dma_latch]
    or al, 80h
    out dx, al
    mov dx, [gus_base]
    mov al, 4Bh
    out dx, al
    add dx, 0Bh
    mov al, [irq_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    mov al, [dma_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 4Bh
    out dx, al
    add dx, 0Bh
    mov al, [irq_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 09h                  ; output/IRQ on; analog input muted
    out dx, al
    popf
    ret

gus_restore_interface:
    cmp word [gus_base], 0
    je .done
    mov dx, [gus_base]
    mov al, 08h                  ; restore line pass-through
    out dx, al
.done:
    ret

gus_reset:
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    call gf1_delay
    call gf1_delay
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 01h
    out dx, al
    call gf1_delay
    call gf1_delay

    mov dx, [gus_base]
    add dx, 100h
    mov al, 03h
    out dx, al
    call gf1_delay
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 41h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 49h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 0Eh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 0CDh                 ; 14 voices gives the GF1's 44.1 kHz rate
    out dx, al

    xor si, si
.voice:
    mov dx, [gus_voice_port]
    mov ax, si
    out dx, al
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    mov dx, [gus_command_port]
    mov al, 0Dh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 0Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 07h
    out dx, al
    inc si
    cmp si, GF1_VOICES
    jb .voice
    call gus_clear_pending
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 07h
    out dx, al
    popf
    ret

gus_clear_pending:
    push ax
    push dx
    mov dx, [gus_status_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 41h
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 49h
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 8Fh
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    pop dx
    pop ax
    ret

gf1_delay:
    push ax
    push cx
    push dx
    mov dx, [gus_dram_port]
    mov cx, 7
.wait:
    in al, dx
    loop .wait
    pop dx
    pop cx
    pop ax
    ret

gus_probe_1mb:
    mov dword [dram_addr], 0
    mov bl, 0A5h
    call gus_poke
    mov dword [dram_addr], 0FFFFFh
    mov bl, 05Ah
    call gus_poke
    mov dword [dram_addr], 0
    call gus_peek
    cmp al, 0A5h
    jne .fail
    mov dword [dram_addr], 0FFFFFh
    call gus_peek
    cmp al, 05Ah
    jne .fail
    clc
    ret
.fail:
    stc
    ret

; BL=value, dram_addr is a 20-bit byte address.
gus_poke:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [dram_addr+2]
    out dx, al
    mov dx, [gus_dram_port]
    mov al, bl
    out dx, al
    popf
    pop dx
    pop ax
    ret

gus_peek:
    push dx
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [dram_addr+2]
    out dx, al
    mov dx, [gus_dram_port]
    in al, dx
    mov [peek_value], al
    popf
    pop dx
    mov al, [peek_value]
    ret

; DS:SI source, CX byte count.  dram_cursor advances.
gus_upload:
    push ax
    push cx
    push dx
    push si
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [dram_cursor+2]
    out dx, al
.byte:
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_cursor]
    out dx, ax
    mov dx, [gus_dram_port]
    lodsb
    out dx, al
    inc word [dram_cursor]
    jnz .next
    inc word [dram_cursor+2]
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [dram_cursor+2]
    out dx, al
.next:
    loop .byte
    popf
    pop si
    pop dx
    pop cx
    pop ax
    ret

; dram_addr source, ES:DI destination, CX byte count.  dram_addr advances.
gus_read:
    push ax
    push cx
    push dx
    push di
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [dram_addr+2]
    out dx, al
.byte:
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr]
    out dx, ax
    mov dx, [gus_dram_port]
    in al, dx
    stosb
    inc word [dram_addr]
    jnz .next
    inc word [dram_addr+2]
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [dram_addr+2]
    out dx, al
.next:
    loop .byte
    popf
    pop di
    pop dx
    pop cx
    pop ax
    ret

; ---------------------------------------------------------------------------
; Asset validation and one-time GF1 DRAM preload

load_sfx_bank:
    mov dx, sfx_filename
    mov ax, 3D00h
    int 21h
    jc .fail
    mov [file_handle], ax
    mov word [bytes_remaining], SFX_BANK_BYTES
    call upload_file_bytes
    jc .close_fail
    call require_file_eof
    jc .close_fail
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
    clc
    ret
.close_fail:
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
.fail:
    stc
    ret

load_all_modules:
    mov byte [load_song], 0
.next:
    call load_one_module
    jc .fail
    inc byte [load_song]
    cmp byte [load_song], SONG_COUNT
    jb .next
    cmp word [dram_cursor+2], 10h
    jae .fail
    clc
    ret
.fail:
    stc
    ret

load_one_module:
    xor bx, bx
    mov bl, [load_song]
    shl bx, 1
    mov dx, [song_filename_table+bx]
    mov ax, 3D00h
    int 21h
    jc .fail
    mov [file_handle], ax
    mov bx, ax
    mov dx, module_header
    mov cx, MOD_HEADER_BYTES
    call dos_read_exact
    jc .close_fail

    mov eax, [module_header+1080]
    cmp eax, 02E4B2E4Dh         ; M.K.
    je .signature_ok
    cmp eax, 034544C46h         ; FLT4
    jne .close_fail
.signature_ok:
    xor ax, ax
    mov al, [module_header+950]
    or al, al
    jz .close_fail
    cmp al, 128
    ja .close_fail
    mov [load_song_length], al
    xor bx, bx
    mov bl, [load_song]
    mov [song_length+bx], al
    mov al, [module_header+951]
    cmp al, [load_song_length]
    jb .restart_ok
    xor al, al
.restart_ok:
    mov [song_restart+bx], al

    ; Preserve the complete order list; it is only 128 bytes per song.
    mov ax, bx
    mov cl, 7
    shl ax, cl
    mov di, song_orders
    add di, ax
    mov si, module_header+952
    mov cx, 128
    rep movsb

    ; Some files retain unplayed patterns after the active order list.  The
    ; full 128-byte table identifies the physical payload boundary, so sample
    ; data is never mistaken for a pattern or vice versa.
    mov si, module_header+952
    mov cx, 128
    xor ax, ax
.max_pattern:
    cmp al, [si]
    jae .not_higher
    mov al, [si]
.not_higher:
    inc si
    loop .max_pattern
    inc ax
    cmp ax, 64                  ; defensive ceiling; this release uses <=18
    ja .close_fail
    mov [load_pattern_count], al

    xor bx, bx
    mov bl, [load_song]
    shl bx, 2
    mov eax, [dram_cursor]
    mov [song_pattern_addr+bx], eax
    xor ax, ax
    mov al, [load_pattern_count]
    mov cl, 10
    shl ax, cl
    mov [bytes_remaining], ax
    call upload_file_bytes
    jc .close_fail

    ; Decode 31 sample headers and stream each sample directly to GF1 RAM.
    xor ax, ax
    mov al, [load_song]
    mov bx, SAMPLES_PER_SONG
    mul bx
    mov [load_sample_index], ax
    mov si, module_header+20
    mov cx, SAMPLES_PER_SONG
.sample:
    push cx
    mov bx, [load_sample_index]
    mov di, bx
    shl bx, 1
    shl di, 2
    mov eax, [dram_cursor]
    mov [sample_start+di], eax

    mov ax, [si+22]
    xchg al, ah
    shl ax, 1
    ; Many classic editors encode an unused instrument as a two-byte sample
    ; but omit those placeholder bytes from the file.  Treat <=2 as empty.
    cmp ax, 2
    ja .sample_length_ready
    xor ax, ax
.sample_length_ready:
    mov [sample_length+bx], ax
    mov [bytes_remaining], ax
    mov ax, [si+26]
    xchg al, ah
    shl ax, 1
    mov [sample_loop_start+bx], ax
    mov ax, [si+28]
    xchg al, ah
    shl ax, 1
    mov [sample_loop_length+bx], ax
    mov al, [si+25]
    cmp al, 64
    jbe .volume_ok
    mov al, 64
.volume_ok:
    mov bx, [load_sample_index]
    mov [sample_volume+bx], al
    cmp byte [si+24], 0         ; target modules have zero finetune
    jne .sample_fail
    call upload_file_bytes
    jc .sample_fail
    inc word [load_sample_index]
    add si, 30
    pop cx
    loop .sample

    call require_file_eof
    jc .close_fail
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
    clc
    ret
.sample_fail:
    pop cx
.close_fail:
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
.fail:
    stc
    ret

; Stream bytes_remaining bytes from file_handle into GF1 RAM.
upload_file_bytes:
    push ax
    push bx
    push cx
    push dx
    push si
.read:
    mov cx, [bytes_remaining]
    jcxz .ok
    cmp cx, IO_BUFFER_BYTES
    jbe .size
    mov cx, IO_BUFFER_BYTES
.size:
    mov bx, [file_handle]
    mov dx, io_buffer
    mov ah, 3Fh
    int 21h
    jc .bad
    cmp ax, cx
    jne .bad
    push cx
    mov si, io_buffer
    call gus_upload
    pop cx
    sub [bytes_remaining], cx
    jmp .read
.ok:
    clc
    jmp .done
.bad:
    stc
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

dos_read_exact:
    mov ah, 3Fh
    int 21h
    jc .bad
    cmp ax, cx
    jne .bad
    clc
    ret
.bad:
    stc
    ret

require_file_eof:
    mov bx, [file_handle]
    mov dx, io_buffer
    mov cx, 1
    mov ah, 3Fh
    int 21h
    jc .bad
    or ax, ax
    jnz .bad
    clc
    ret
.bad:
    stc
    ret

; Generate a tiny original sawtooth solely for /T.  It verifies a non-music
; GF1 voice without embedding any third-party sample.
make_test_sample:
    mov eax, [dram_cursor]
    mov [test_sample_addr], eax
    mov di, io_buffer
    mov cx, 256
    xor ax, ax
.generate:
    stosb
    inc al
    loop .generate
    mov si, io_buffer
    mov cx, 256
    call gus_upload
    ret

; ---------------------------------------------------------------------------
; DOS child, vectors, and the transient in-memory hook

exec_game:
    push cs
    pop ds
    push cs
    pop es
    mov word [exec_params], 0
    mov ax, [psp_segment]
    mov word [exec_params+2], exec_tail
    mov word [exec_params+4], ax
    mov word [exec_params+6], 5Ch
    mov word [exec_params+8], ax
    mov word [exec_params+10], 6Ch
    mov word [exec_params+12], ax
    mov dx, game_filename
    mov bx, exec_params
    mov ax, 4B00h
    int 21h
    ret

install_vectors:
    mov ax, 3521h
    int 21h
    mov [old_int21], bx
    mov [old_int21+2], es
    mov ax, 3565h
    int 21h
    mov [old_int65], bx
    mov [old_int65+2], es
    mov ax, 3566h
    int 21h
    mov [old_int66], bx
    mov [old_int66+2], es

    mov ax, [gus_irq]
    cmp ax, 7
    jbe .master
    add ax, 68h
    jmp .vector
.master:
    add ax, 08h
.vector:
    mov [irq_vector], al
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    in al, 21h
    mov [old_pic_master], al
    in al, 0A1h
    mov [old_pic_slave], al

    push ds
    push cs
    pop ds
    mov dx, int65_handler
    mov ax, 2565h
    int 21h
    mov dx, int66_handler
    mov ax, 2566h
    int 21h
    mov dx, gus_irq_handler
    mov ah, 25h
    mov al, [irq_vector]
    int 21h
    mov dx, int21_handler
    mov ax, 2521h
    int 21h
    pop ds

    pushf
    cli
    mov ax, [gus_irq]
    cmp ax, 7
    ja .slave_irq
    mov cl, al
    mov bl, 1
    shl bl, cl
    not bl
    in al, 21h
    and al, bl
    out 21h, al
    jmp .unmasked
.slave_irq:
    sub al, 8
    mov cl, al
    mov bl, 1
    shl bl, cl
    not bl
    in al, 0A1h
    and al, bl
    out 0A1h, al
    in al, 21h
    and al, 0FBh
    out 21h, al
.unmasked:
    popf
    mov byte [vectors_installed], 1
    ret

restore_vectors:
    cmp byte [vectors_installed], 1
    jne .done
    call gus_timer_stop
    pushf
    cli
    mov al, [old_pic_master]
    out 21h, al
    mov al, [old_pic_slave]
    out 0A1h, al
    popf

    mov dx, [old_irq]
    mov ax, [old_irq+2]
    mov ds, ax
    mov ah, 25h
    mov al, [cs:irq_vector]
    int 21h
    mov dx, [cs:old_int65]
    mov ax, [cs:old_int65+2]
    mov ds, ax
    mov ax, 2565h
    int 21h
    mov dx, [cs:old_int66]
    mov ax, [cs:old_int66+2]
    mov ds, ax
    mov ax, 2566h
    int 21h
    mov dx, [cs:old_int21]
    mov ax, [cs:old_int21+2]
    mov ds, ax
    mov ax, 2521h
    int 21h
    push cs
    pop ds
    mov byte [vectors_installed], 0
.done:
    ret

cleanup:
    mov byte [music_active], 0
    mov byte [sfx_active], 0
    call gus_quiet
    call restore_vectors
    call gus_restore_interface
    ret

; The validated EXEPACK image makes one resize call at a stable return address
; after materializing the original code.  Its interrupt frame gives us the
; relocated code segment without scanning or modifying the file.
int21_handler:
    push bp
    mov bp, sp
    pushf
    pusha
    push ds
    push es
    push cs
    pop ds
    cld
    cmp byte [patch_installed], 1
    je .chain
    cmp ah, 4Ah
    jne .chain
    cmp word [ss:bp+2], UNPACK_RETURN_IP
    jne .chain
    mov ax, [ss:bp+4]
    mov es, ax
    mov byte [es:PATCH_MUSIC_OFF], 0CDh
    mov byte [es:PATCH_MUSIC_OFF+1], 65h
    mov byte [es:PATCH_MUSIC_OFF+2], 0C3h
    mov byte [es:PATCH_STOP_OFF], 031h
    mov byte [es:PATCH_STOP_OFF+1], 0D2h
    mov byte [es:PATCH_STOP_OFF+2], 0CDh
    mov byte [es:PATCH_STOP_OFF+3], 65h
    mov byte [es:PATCH_STOP_OFF+4], 0C3h
    mov byte [es:PATCH_SFX_OFF], 0CDh
    mov byte [es:PATCH_SFX_OFF+1], 66h
    mov byte [es:PATCH_SFX_OFF+2], 0C3h
    mov [patch_segment], ax
    add ax, SOUND_SEG_DELTA
    mov [game_sound_segment], ax
    mov byte [patch_installed], 1
.chain:
    pop es
    pop ds
    popa
    popf
    pop bp
    jmp far [cs:old_int21]

; ---------------------------------------------------------------------------
; Software interrupt hooks called by the three-byte child stubs

int65_handler:
    mov [cs:request_segment], ds
    mov [cs:request_offset], dx
    pusha
    push ds
    push es
    push cs
    pop ds
    cld
    cmp word [request_offset], 0
    jne .song
    mov byte [music_active], 0
    call mute_music_voices
    jmp .done
.song:
    call identify_song
    jc .done
    call select_song
    cmp byte [run_mode], 3
    jne .done
    cmp byte [integration_fired], 1
    je .done
    mov byte [integration_fired], 1
    xor bx, bx
    call start_sfx_request
    mov bx, [total_ticks]
    add bx, SELFTEST_TICKS
.integration_wait:
    cmp [total_ticks], bx
    jae .integration_exit
    sti
    hlt
    jmp .integration_wait
.integration_exit:
    mov ax, 4C00h
    int 21h
.done:
    pop es
    pop ds
    popa
    iret

; Return AL=song number and CF clear for an exact NUL-terminated filename.
identify_song:
    mov ax, [request_segment]
    mov es, ax
    xor bx, bx
.candidate:
    mov di, [request_offset]
    mov si, bx
    shl si, 1
    mov si, [song_filename_table+si]
.compare:
    mov al, [si]
    cmp al, [es:di]
    jne .next
    inc si
    inc di
    or al, al
    jnz .compare
    mov ax, bx
    clc
    ret
.next:
    inc bx
    cmp bx, SONG_COUNT
    jb .candidate
    stc
    ret

int66_handler:
    mov [cs:requested_sfx], bl
    pusha
    push ds
    push es
    push cs
    pop ds
    xor bx, bx
    mov bl, [requested_sfx]
    call start_sfx_request
    pop es
    pop ds
    popa
    iret

; BX=game effect number.  The command stream remains in the child image; only
; its public behavior is reimplemented here.
start_sfx_request:
    cmp bx, 42
    jae .done
    mov ax, [game_sound_segment]
    or ax, ax
    jz .done
    mov es, ax
    shl bx, 1
    mov ax, [es:SFX_SCRIPT_TABLE+bx]
    mov [sfx_script_start], ax
    mov [sfx_script_current], ax
    mov word [sfx_delay], 0
    mov byte [sfx_slide], 0
    mov byte [sfx_active], 1
.done:
    ret

; ---------------------------------------------------------------------------
; GF1 timer and IRQ

gus_timer_start:
    cmp byte [timer_started], 1
    je .done
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 46h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 6                    ; (256-6)*80 us = 20 ms = 50 Hz
    out dx, al
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 04h
    out dx, al
    mov byte [timer_control_shadow], 04h
    mov dx, [gus_timer_control_port]
    mov al, 04h
    out dx, al
    mov dx, [gus_timer_data_port]
    mov al, 01h
    out dx, al
    mov byte [timer_started], 1
    popf
.done:
    ret

gus_timer_stop:
    cmp byte [timer_started], 1
    jne .done
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_timer_control_port]
    mov al, 04h
    out dx, al
    mov dx, [gus_timer_data_port]
    xor al, al
    out dx, al
    mov byte [timer_started], 0
    popf
.done:
    ret

gus_irq_handler:
    pushf
    push ax
    push dx
    mov dx, [cs:gus_status_port]
    in al, dx
    test al, 04h
    jnz .ours
    pop dx
    pop ax
    popf
    jmp far [cs:old_irq]
.ours:
    push bx
    push cx
    push si
    push di
    push bp
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    cld

    ; Acknowledge/re-arm timer 1 before doing bounded tracker work.
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [timer_control_shadow]
    and al, 0FBh
    out dx, al
    or al, 04h
    out dx, al

    inc word [total_ticks]
    cmp byte [music_active], 1
    jne .sfx
    call tracker_tick
.sfx:
    add word [sfx_phase], 4069    ; original SB stream callback ~=40.69 Hz
    cmp word [sfx_phase], 5000
    jb .voice_irq
    sub word [sfx_phase], 5000
    call sfx_tick
.voice_irq:
    mov dx, [gus_command_port]
    mov al, 8Fh
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx

    cmp word [gus_irq], 7
    jbe .master_eoi
    mov al, 20h
    out 0A0h, al
.master_eoi:
    mov al, 20h
    out 20h, al
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    pop dx
    pop ax
    popf
    iret

; ---------------------------------------------------------------------------
; Original SFX command semantics, with GF1 voices replacing software mixing

sfx_tick:
    cmp byte [sfx_active], 1
    jne .done
    mov ax, [game_sound_segment]
    or ax, ax
    jz .stop
    mov es, ax
    cmp word [sfx_delay], 0
    je .commands
    dec word [sfx_delay]
    call sfx_slide_tick
    cmp word [sfx_delay], 0
    jne .done
    mov byte [sfx_slide], 0
    jmp .done
.commands:
    mov si, [sfx_script_current]
.next:
    mov al, [es:si]
    inc si
    test al, 80h
    jz .note
    cmp al, 80h
    je .skip_parameter
    cmp al, 81h
    je .skip_parameter
    cmp al, 83h
    je .skip_parameter
    cmp al, 84h
    je .skip_parameter
    cmp al, 82h
    je .duration
    cmp al, 85h
    je .sample
    cmp al, 86h
    je .stop_save
    cmp al, 87h
    je .loop
    cmp al, 88h
    je .next
    cmp al, 89h
    je .next
    cmp al, 8Ah
    je .slide_up
    cmp al, 8Bh
    je .slide_down
    jmp .stop_save
.skip_parameter:
    inc si
    jmp .next
.duration:
    xor ax, ax
    mov al, [es:si]
    inc si
    shl ax, 4
    mov [sfx_duration], ax
    jmp .next
.sample:
    xor bx, bx
    mov bl, [es:si]
    inc si
    shl bx, 1
    mov bx, [es:053A8h+bx]
    cmp bx, 10
    jb .stop_save
    sub bx, 10
    cmp bx, 29
    jae .stop_save
    shl bx, 2
    mov ax, [es:SFX_DESCRIPTOR_TABLE+bx]
    mov [sfx_sample_begin], ax
    mov ax, [es:SFX_DESCRIPTOR_TABLE+bx+2]
    mov [sfx_sample_end], ax
    jmp .next
.loop:
    mov si, [sfx_script_start]
    jmp .next
.slide_up:
    mov byte [sfx_slide], 1
    jmp .next
.slide_down:
    mov byte [sfx_slide], -1
    jmp .next
.note:
    cmp al, 97
    jae .stop_save
    xor bx, bx
    mov bl, al
    shl bx, 1
    mov ax, [es:SFX_NOTE_LOW_TABLE+bx]
    mov [sfx_step], ax
    mov ax, [es:SFX_NOTE_HIGH_TABLE+bx]
    mov [sfx_step+2], ax
    mov ax, [sfx_duration]
    mov [sfx_delay], ax
    mov [sfx_script_current], si
    call play_sfx_note
    ret
.stop_save:
    mov [sfx_script_current], si
.stop:
    mov byte [sfx_active], 0
.done:
    ret

sfx_slide_tick:
    mov al, [sfx_slide]
    or al, al
    jz .done
    cmp al, 1
    jne .down
    sub dword [sfx_step], 64
    jmp .apply
.down:
    add dword [sfx_step], 64
.apply:
    call sfx_step_to_frequency
    mov bx, ax
    mov al, [sfx_current_voice]
    call gf1_voice_frequency
.done:
    ret

; Convert the game's 16.16 step at a 10,416.67 Hz SB stream rate into the
; GF1 frequency-control word at 44.1 kHz.  386 arithmetic keeps this exact.
sfx_step_to_frequency:
    mov eax, [sfx_step]
    imul eax, eax, 625
    add eax, 84672
    xor edx, edx
    mov ecx, 169344
    div ecx
    and ax, 0FFFEh
    ret

play_sfx_note:
    mov ax, [sfx_sample_end]
    cmp ax, [sfx_sample_begin]
    jbe .done
    movzx eax, word [sfx_sample_begin]
    mov [voice_begin], eax
    mov [voice_loop], eax
    movzx eax, word [sfx_sample_end]
    dec eax
    mov [voice_end], eax
    call sfx_step_to_frequency
    mov [voice_frequency], ax
    call sfx_volume_word
    mov [voice_volume], ax
    mov byte [voice_mode], 0

    xor bx, bx
    mov bl, [sfx_next_voice]
    mov al, bl
    add al, 4
    mov [voice_number], al
    mov [sfx_current_voice], al
    inc bl
    cmp bl, 10
    jb .round_robin
    xor bl, bl
.round_robin:
    mov [sfx_next_voice], bl
    mov byte [voice_pan], 7
    call gf1_start_voice
    inc word [sfx_notes]
.done:
    ret

play_test_sample:
    mov eax, [test_sample_addr]
    mov [voice_begin], eax
    mov [voice_loop], eax
    add eax, 255
    mov [voice_end], eax
    mov word [voice_frequency], 512
    mov word [voice_volume], 0E800h
    mov byte [voice_number], 4
    mov byte [voice_pan], 7
    mov byte [voice_mode], 08h
    call gf1_start_voice
    inc word [sfx_notes]
    ret

; ---------------------------------------------------------------------------
; Four-channel MOD player.  Only effects present in the validated assets are
; implemented: arpeggio, portamento down, volume slide, set volume, pattern
; break, and speed.  Pattern rows are fetched from GF1 RAM 16 bytes at a time.

select_song:
    cmp al, SONG_COUNT
    jae .done
    mov byte [music_active], 0
    push ax
    call mute_music_voices
    pop ax
    mov [current_song], al
    mov byte [tracker_speed], 6
    mov byte [tracker_tick_index], 0
    mov byte [tracker_order], 0
    mov word [tracker_row], 0
    mov byte [tracker_next_order], 0
    mov word [tracker_next_row], 0
    push ds
    pop es
    mov di, channel_sample
    mov cx, 4
    mov al, 0FFh
    rep stosb
    xor ax, ax
    mov di, channel_period
    mov cx, 4
    rep stosw
    mov di, channel_volume
    mov cx, 4
    rep stosb
    mov di, channel_effect
    mov cx, 4
    rep stosb
    mov di, channel_param
    mov cx, 4
    rep stosb
    mov di, channel_porta
    mov cx, 4
    rep stosb
    inc word [songs_started]
    mov byte [music_active], 1
.done:
    ret

tracker_tick:
    cmp byte [tracker_tick_index], 0
    jne .effect_tick
    call tracker_process_row
    mov al, [tracker_speed]
    cmp al, 1
    jbe .advance
    inc byte [tracker_tick_index]
    ret
.effect_tick:
    call tracker_effect_tick
    inc byte [tracker_tick_index]
    mov al, [tracker_tick_index]
    cmp al, [tracker_speed]
    jb .done
.advance:
    mov byte [tracker_tick_index], 0
    mov al, [tracker_next_order]
    mov [tracker_order], al
    mov ax, [tracker_next_row]
    mov [tracker_row], ax
.done:
    ret

tracker_process_row:
    ; Default successor is the next row, wrapping through the song restart.
    mov al, [tracker_order]
    mov [tracker_next_order], al
    mov ax, [tracker_row]
    inc ax
    mov [tracker_next_row], ax
    cmp ax, 64
    jb .successor_ready
    mov word [tracker_next_row], 0
    inc byte [tracker_next_order]
    call normalize_next_position
.successor_ready:

    ; Resolve current order -> pattern -> 16-byte row address.
    xor ax, ax
    mov al, [current_song]
    mov cl, 7
    shl ax, cl
    mov bx, ax
    xor ax, ax
    mov al, [tracker_order]
    add bx, ax
    movzx edx, byte [song_orders+bx]
    shl edx, 10
    xor bx, bx
    mov bl, [current_song]
    shl bx, 2
    mov eax, [song_pattern_addr+bx]
    add eax, edx
    movzx edx, word [tracker_row]
    shl edx, 4
    add eax, edx
    mov [dram_addr], eax
    push cs
    pop es
    mov di, row_buffer
    mov cx, 16
    call gus_read

    mov si, row_buffer
    xor di, di
.channel:
    call tracker_process_cell
    add si, 4
    inc di
    cmp di, 4
    jb .channel
    ret

normalize_next_position:
    xor bx, bx
    mov bl, [current_song]
    mov al, [tracker_next_order]
    cmp al, [song_length+bx]
    jb .done
    mov al, [song_restart+bx]
    mov [tracker_next_order], al
.done:
    ret

tracker_process_cell:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov byte [temp_trigger], 0
    mov byte [temp_volume_changed], 0

    mov al, [si]
    and al, 0F0h
    mov ah, [si+2]
    shr ah, 4
    or al, ah
    mov [temp_sample], al
    mov ah, [si]
    and ah, 0Fh
    mov al, [si+1]
    mov [temp_period], ax
    mov al, [si+2]
    and al, 0Fh
    mov [temp_effect], al
    mov [channel_effect+di], al
    mov al, [si+3]
    mov [temp_param], al
    mov [channel_param+di], al

    mov al, [temp_sample]
    or al, al
    jz .period
    dec al
    cmp al, 30
    ja .period
    mov [channel_sample+di], al
    call channel_sample_index
    mov al, [sample_volume+bx]
    mov [channel_volume+di], al
    mov byte [temp_volume_changed], 1
.period:
    mov ax, [temp_period]
    or ax, ax
    jz .effect
    mov bx, di
    shl bx, 1
    mov [channel_period+bx], ax
    cmp byte [channel_sample+di], 30
    ja .effect
    mov byte [temp_trigger], 1

.effect:
    mov al, [temp_effect]
    cmp al, 02h
    je .porta
    cmp al, 0Ah
    je .volume_slide
    cmp al, 0Ch
    je .set_volume
    cmp al, 0Dh
    je .pattern_break
    cmp al, 0Fh
    je .set_speed
    jmp .hardware
.porta:
    mov al, [temp_param]
    or al, al
    jz .hardware
    mov [channel_porta+di], al
    jmp .hardware
.volume_slide:
    jmp .hardware
.set_volume:
    mov al, [temp_param]
    cmp al, 64
    jbe .volume_valid
    mov al, 64
.volume_valid:
    mov [channel_volume+di], al
    mov byte [temp_volume_changed], 1
    jmp .hardware
.pattern_break:
    mov al, [temp_param]
    mov dl, al
    and al, 0Fh
    and dl, 0F0h
    shr dl, 4
    mov dh, al
    mov al, dl
    mov bl, 10
    mul bl
    add al, dh
    xor ah, ah
    cmp ax, 63
    jbe .break_row_ok
    xor ax, ax
.break_row_ok:
    mov [tracker_next_row], ax
    mov al, [tracker_order]
    inc al
    mov [tracker_next_order], al
    call normalize_next_position
    jmp .hardware
.set_speed:
    mov al, [temp_param]
    or al, al
    jz .hardware
    cmp al, 31
    ja .hardware
    mov [tracker_speed], al

.hardware:
    cmp byte [temp_trigger], 1
    jne .no_trigger
    call trigger_music_channel
    jmp .volume
.no_trigger:
    ; Restore the base pitch on every row; this also ends arpeggio cleanly.
    mov bx, di
    shl bx, 1
    cmp word [channel_period+bx], 0
    je .volume
    call update_music_frequency
.volume:
    cmp byte [temp_volume_changed], 1
    jne .done
    call update_music_volume
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

tracker_effect_tick:
    xor di, di
.channel:
    mov al, [channel_effect+di]
    cmp al, 00h
    je .arpeggio
    cmp al, 02h
    je .porta
    cmp al, 0Ah
    je .volume_slide
    jmp .next
.arpeggio:
    mov al, [channel_param+di]
    or al, al
    jz .next
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .next
    call period_to_frequency
    movzx eax, ax
    mov al, [tracker_tick_index]
    xor ah, ah
    mov bl, 3
    div bl                      ; AH=tick modulo three
    mov bl, ah
    xor bh, bh
    mov al, [channel_param+di]
    cmp bl, 1
    je .arp_high
    cmp bl, 2
    je .arp_low
    xor bx, bx
    jmp .arp_ratio
.arp_high:
    shr al, 4
    mov bl, al
    jmp .arp_ratio
.arp_low:
    and al, 0Fh
    mov bl, al
.arp_ratio:
    shl bx, 1
    movzx ebx, word [arpeggio_ratio+bx]
    ; Recompute base frequency after byte division clobbered AX.
    push bx
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    call period_to_frequency
    movzx eax, ax
    pop bx
    imul eax, ebx
    add eax, 128
    shr eax, 8
    and ax, 0FFFEh
    mov bx, ax
    mov ax, di
    call gf1_voice_frequency
    jmp .next
.porta:
    xor ax, ax
    mov al, [channel_porta+di]
    or ax, ax
    jz .next
    mov bx, di
    shl bx, 1
    add [channel_period+bx], ax
    call update_music_frequency
    jmp .next
.volume_slide:
    mov al, [channel_param+di]
    mov ah, al
    shr al, 4
    and ah, 0Fh
    xor bx, bx
    mov bl, [channel_volume+di]
    or al, al
    jz .slide_down
    xor ah, ah
    add bx, ax
    cmp bx, 64
    jbe .slide_store
    mov bx, 64
    jmp .slide_store
.slide_down:
    xor al, al
    xchg al, ah
    xor ah, ah
    cmp bx, ax
    jae .subtract
    xor bx, bx
    jmp .slide_store
.subtract:
    sub bx, ax
.slide_store:
    mov [channel_volume+di], bl
    call update_music_volume
.next:
    inc di
    cmp di, 4
    jb .channel
    ret

; DI=channel, returns BX=global sample metadata index.
channel_sample_index:
    xor ax, ax
    mov al, [current_song]
    mov dl, SAMPLES_PER_SONG
    mul dl
    xor bx, bx
    mov bl, [channel_sample+di]
    add bx, ax
    ret

trigger_music_channel:
    call channel_sample_index
    mov bp, bx
    shl bx, 1
    mov ax, [sample_length+bx]
    or ax, ax
    jz .stop
    mov [voice_sample_length], ax
    mov ax, [sample_loop_start+bx]
    mov [voice_loop_offset], ax
    mov ax, [sample_loop_length+bx]
    mov [voice_loop_length], ax
    mov bx, bp
    shl bx, 2
    mov eax, [sample_start+bx]
    mov [voice_begin], eax
    mov [voice_loop], eax
    movzx ebx, word [voice_loop_offset]
    add [voice_loop], ebx
    cmp word [voice_loop_length], 2
    jbe .no_loop
    mov eax, [voice_loop]
    movzx ebx, word [voice_loop_length]
    dec ebx
    add eax, ebx
    mov [voice_end], eax
    mov byte [voice_mode], 08h
    jmp .address_ready
.no_loop:
    mov eax, [voice_begin]
    movzx ebx, word [voice_sample_length]
    dec ebx
    add eax, ebx
    mov [voice_end], eax
    mov byte [voice_mode], 0
.address_ready:
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .stop
    call period_to_frequency
    mov [voice_frequency], ax
    mov ax, di
    mov [voice_number], al
    mov bx, di
    mov al, [music_pan+bx]
    mov [voice_pan], al
    mov al, [channel_volume+di]
    call music_volume_word
    mov [voice_volume], ax
    call gf1_start_voice
    ret
.stop:
    mov ax, di
    call gf1_stop_voice
    ret

update_music_frequency:
    push ax
    push bx
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .done
    call period_to_frequency
    mov bx, ax
    mov ax, di
    call gf1_voice_frequency
.done:
    pop bx
    pop ax
    ret

update_music_volume:
    push ax
    push bx
    mov al, [channel_volume+di]
    call music_volume_word
    mov bx, ax
    mov ax, di
    call gf1_voice_volume
    pop bx
    pop ax
    ret

period_to_frequency:
    push bx
    push dx
    mov bx, ax
    or bx, bx
    jz .zero
    shr ax, 1
    add ax, 41179
    xor dx, dx
    div bx
    shl ax, 1
    jmp .done
.zero:
    xor ax, ax
.done:
    pop dx
    pop bx
    ret

music_volume_word:
    push bx
    push cx
    xor ah, ah
    mov bl, [music_master]
    mul bl
    mov cl, 6
    shr ax, cl
    cmp ax, 64
    jbe .index
    mov ax, 64
.index:
    shl ax, 1
    mov bx, ax
    mov ax, [volume_table+bx]
    pop cx
    pop bx
    ret

sfx_volume_word:
    push bx
    xor ah, ah
    mov al, [sfx_master]
    shl ax, 1
    mov bx, ax
    mov ax, [volume_table+bx]
    pop bx
    ret

; ---------------------------------------------------------------------------
; GF1 voice programming

gf1_start_voice:
    pushf
    cli
    push ax
    push bx
    push cx
    push dx
    mov dx, [gus_voice_port]
    mov al, [voice_number]
    out dx, al

    ; Stop oscillator and volume ramp while replacing all voice registers.
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    mov dx, [gus_command_port]
    mov al, 0Dh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax

    mov byte [voice_addr_register], 0Ah
    mov eax, [voice_begin]
    mov [voice_addr], eax
    call gf1_write_voice_address
    mov byte [voice_addr_register], 02h
    mov eax, [voice_loop]
    mov [voice_addr], eax
    call gf1_write_voice_address
    mov byte [voice_addr_register], 04h
    mov eax, [voice_end]
    mov [voice_addr], eax
    call gf1_write_voice_address

    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_frequency]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 0Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [voice_pan]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_volume]
    out dx, ax
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [voice_mode]
    and al, 0FCh
    out dx, al
    call gf1_delay
    out dx, al
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

gf1_write_voice_address:
    push ax
    push bx
    push cx
    push dx
    mov ax, [voice_addr]
    mov cx, [voice_addr+2]
    mov bx, cx
    shr ax, 7
    shr cx, 7
    shl bx, 9
    or ax, bx
    mov bx, ax
    mov dx, [gus_command_port]
    mov al, [voice_addr_register]
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    mov dx, [gus_command_port]
    mov al, [voice_addr_register]
    inc al
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_addr]
    shl ax, 9
    out dx, ax
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; AL=voice, BX=frequency word
gf1_voice_frequency:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    popf
    pop dx
    pop ax
    ret

; AL=voice, BX=current-volume register value
gf1_voice_volume:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    popf
    pop dx
    pop ax
    ret

; AL=voice
gf1_stop_voice:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    popf
    pop dx
    pop ax
    ret

mute_music_voices:
    xor si, si
.voice:
    mov ax, si
    call gf1_stop_voice
    inc si
    cmp si, 4
    jb .voice
    ret

gus_quiet:
    cmp word [gus_base], 0
    je .done
    pushf
    cli
    push ax
    push si
    xor si, si
.voice:
    mov ax, si
    call gf1_stop_voice
    inc si
    cmp si, GF1_VOICES
    jb .voice
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    pop si
    pop ax
    popf
.done:
    ret

; ---------------------------------------------------------------------------
; Resident data

msg_banner        db 13,10,'JP2GUS 1.0 - native Gravis UltraSound GF1 audio',13,10,'$'
msg_bad_args      db 'Usage: JP2GUS [/T|/I] [/J|/NJ] [/P-100..100] [/M0..100] [/S0..100]',13,10,'$'
msg_bad_target    db 'ERROR: ROBOCOD.EXE is missing or is not the supported exact release.',13,10,'$'
msg_bad_config    db 'ERROR: ULTRASND must be base,DMA,DMA,IRQ,IRQ (example 240,7,7,7,7).',13,10,'$'
msg_no_gus        db 'ERROR: a writable 1 MiB GF1 RAM was not found at the ULTRASND port.',13,10,'$'
msg_bad_assets    db 'ERROR: an audio asset is missing, truncated, or not the expected MOD format.',13,10,'$'
msg_no_memory     db 'ERROR: DOS could not resize the launcher memory block.',13,10,'$'
msg_exec_failed   db 'ERROR: DOS could not execute ROBOCOD.EXE; DOS code 0x','$'
msg_patch_missing db 'ERROR: the validated game did not reach the expected unpack handoff.',13,10,'$'
msg_run_ok        db 'JP2GUS: in-memory hooks removed; vectors and GUS interface restored.',13,10,'$'
msg_test_start    db 'Self-test: four-channel title music plus an original GF1 test tone (5 s)...',13,10,'$'
msg_test_ok       db 'Self-test passed: the GF1 timer and both voice pools ran.',13,10,'$'
msg_test_failed   db 'Self-test failed: no GF1 timer interrupts arrived.',13,10,'$'
msg_counts        db 'GF1 events: songs=0x','$'
msg_count_sfx     db ' sfx-notes=0x','$'
msg_crlf          db 13,10,'$'
msg_settings_joy  db 'Settings: joystick=','$'
msg_on            db 'on','$'
msg_off           db 'off','$'
msg_settings_music db ' music=','$'
msg_settings_sfx  db '% sfx=','$'
msg_settings_pan  db '% pan=','$'
msg_percent_crlf  db '%',13,10,'$'

ultrasnd_key      db 'ULTRASND='
game_filename     db 'ROBOCOD.EXE',0
sfx_filename      db 'SAMPLES.BIN',0
song_name_0       db 'TITLE1',0
song_name_1       db 'CATLOTS',0
song_name_2       db 'BATH1',0
song_name_3       db 'TOYS1',0
song_name_4       db 'XMAS1',0
song_name_5       db 'MOD.BON',0
song_name_6       db 'MOD.ELG',0
song_filename_table:
    dw song_name_0, song_name_1, song_name_2, song_name_3
    dw song_name_4, song_name_5, song_name_6
exec_tail         db 3,' ','+','J',13

irq_lut           db 0,0,1,3,0,2,0,4,0,0,0,5,6,0,0,7
dma_lut           db 0,1,0,2,0,3,4,5
music_pan         db 3,12,12,3
music_master      db 48
sfx_master        db 52
music_percent     db 75
sfx_percent       db 81
pan_percent       db 60
pan_reverse       db 0
joystick_enabled  db 1

; Q8.8 values for 2^(semitones/12), rounded independently.
arpeggio_ratio:
    dw 256,271,287,304,323,342,362,384
    dw 407,431,456,483,512,542,575,609

; Linear 0..64 loudness indices encoded for the GF1 exponent/mantissa volume.
volume_table:
    dw 00000h,09FF0h,0AFF0h,0B800h,0BFF0h,0C400h,0C800h,0CC00h
    dw 0CFF0h,0D200h,0D400h,0D600h,0D800h,0DA00h,0DC00h,0DE00h
    dw 0DFF0h,0E100h,0E200h,0E300h,0E400h,0E500h,0E600h,0E700h
    dw 0E800h,0E900h,0EA00h,0EB00h,0EC00h,0ED00h,0EE00h,0EF00h
    dw 0EFF0h,0F080h,0F100h,0F180h,0F200h,0F280h,0F300h,0F380h
    dw 0F400h,0F480h,0F500h,0F580h,0F600h,0F680h,0F700h,0F780h
    dw 0F800h,0F880h,0F900h,0F980h,0FA00h,0FA80h,0FB00h,0FB80h
    dw 0FC00h,0FC80h,0FD00h,0FD80h,0FE00h,0FE80h,0FF00h,0FF80h
    dw 0FFF0h

psp_segment       dw 0
run_mode          db 0
integration_fired db 0
exec_failed       db 0
exec_error        dw 0
child_exit_code   db 0
patch_installed   db 0
patch_segment     dw 0
game_sound_segment dw 0
request_segment   dw 0
request_offset    dw 0
requested_sfx     db 0

gus_base          dw 0
gus_dma1          dw 0
gus_dma2          dw 0
gus_irq           dw 0
gus_midi_irq      dw 0
gus_voice_port    dw 0
gus_command_port  dw 0
gus_data_low_port dw 0
gus_data_high_port dw 0
gus_status_port   dw 0
gus_timer_control_port dw 0
gus_timer_data_port dw 0
gus_dram_port     dw 0
irq_latch         db 0
dma_latch         db 0
old_pic_master    db 0
old_pic_slave     db 0
irq_vector        db 0
vectors_installed db 0
timer_started     db 0
timer_control_shadow db 0
peek_value        db 0
dram_addr         dd 0

old_int21         dd 0
old_int65         dd 0
old_int66         dd 0
old_irq           dd 0
exec_params       times 14 db 0

total_ticks       dw 0
bios_tick_start   dw 0
songs_started     dw 0
sfx_notes         dw 0

music_active      db 0
current_song      db 0FFh
tracker_speed     db 6
tracker_tick_index db 0
tracker_order     db 0
tracker_row       dw 0
tracker_next_order db 0
tracker_next_row  dw 0
channel_sample    times 4 db 0FFh
channel_period    times 4 dw 0
channel_volume    times 4 db 0
channel_effect    times 4 db 0
channel_param     times 4 db 0
channel_porta     times 4 db 0
row_buffer        times 16 db 0

temp_sample       db 0
temp_effect       db 0
temp_param        db 0
temp_period       dw 0
temp_trigger      db 0
temp_volume_changed db 0

song_pattern_addr times SONG_COUNT dd 0
song_length       times SONG_COUNT db 0
song_restart      times SONG_COUNT db 0
song_orders       times SONG_COUNT*128 db 0
sample_start      times TOTAL_MUSIC_SAMPLES dd 0
sample_length     times TOTAL_MUSIC_SAMPLES dw 0
sample_loop_start times TOTAL_MUSIC_SAMPLES dw 0
sample_loop_length times TOTAL_MUSIC_SAMPLES dw 0
sample_volume     times TOTAL_MUSIC_SAMPLES db 0
test_sample_addr  dd 0

sfx_active        db 0
sfx_phase         dw 0
sfx_script_start  dw 0
sfx_script_current dw 0
sfx_duration      dw 0
sfx_delay         dw 0
sfx_sample_begin  dw 0
sfx_sample_end    dw 0
sfx_slide         db 0
sfx_step          dd 0
sfx_next_voice    db 0
sfx_current_voice db 4

voice_number      db 0
voice_mode        db 0
voice_pan         db 7
voice_frequency   dw 0
voice_volume      dw 0
voice_begin       dd 0
voice_loop        dd 0
voice_end         dd 0
voice_sample_length dw 0
voice_loop_offset dw 0
voice_loop_length dw 0
voice_addr_register db 0
voice_addr        dd 0

stack_space       times 1024 db 0
stack_top:
resident_end:

; Startup-only workspace.  DOS releases this tail before EXEC.
file_handle       dw 0FFFFh
file_count        dd 0
file_crc          dd 0
bytes_remaining   dw 0
dram_cursor       dd 0
load_song         db 0
load_song_length  db 0
load_pattern_count db 0
load_sample_index dw 0
module_header     times MOD_HEADER_BYTES db 0
io_buffer         times IO_BUFFER_BYTES db 0

RESIDENT_PARAS equ ((resident_end - $$ + 100h + 15) / 16)
