# 1 "dvb/dvbs2arm_1v30.S"
# 1 "<built-in>"
# 1 "<command-line>"
# 31 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 32 "<command-line>" 2
# 1 "dvb/dvbs2arm_1v30.S"



@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: dvbs2arm.S
@:
@: (C) Brian Jordan, G4EWJ, 14 April 2018, g4ewj at yahoo dot com
@:
@: DVB-S2 packet to short frame converter for ARM
@: Accepts 188 byte packets and produces DVB-S2 frames to send to an IQ modulator
@: Supports FEC 1/4 or 3/4 only
@: Supports rolloff 0.20, 0.25, 0.35
@: For QPSK modulation only
@:
@: For FEC 3/4,
@: The optimum packet processing time is 25us on an RPI0 and 15us on an RPI3
@: The equivalent frame processing time is 195us on an RPI0 and 115us on an RPI3
@:
@: Parts derived from DATV-Express and RPiDATV
@: Thanks to G4GUO and F5OEO for their help
@:
@: This software is provided free for non-commercial amateur radio use.
@: It has no warranty of fitness for any purpose.
@: Generation of a DVB-S2 transport stream may require a licence.
@: Use at your own risk.
@:
@: If @ is not the comment character for your assembler,
@: search and replace @: with yours.
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: Change history
@:
@: 2018-04-18 v1.30 corrected rolloff value in BB header
@: 2018-02-22 v1.29 corrected some typos and added more comments
@: 2018-02-12 v1.28 added FEC 1/4, made rolloff selectable, added efficiency calculation
@: 2018-02-02 v1.07 symbol scrambler/splitter speed increased
@: corrected some typos and added more comments
@: 2018-01-28 v1.01 first release
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: External entry points
@:
@: Only these external entry points are required
@: The calling requirements for other routines are shown for information only
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

.global _dvbs2arm_control
.global _dvbs2arm_process_packet


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: Bit fields for short frame FEC 3/4 QPSK
@:
@: ********* DATAFIELD 11632
@: ****************** BBFRAME 11712
@: ************************* BCHFRAME 11880
@: ********************************** FECFRAME 16200
@: ******************************************** PLFRAME 16380
@: PLHEADER BBHEADER DATAFIELD BCH LDPC
@: 180 80 11632 168 4320
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: Definitions
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 123 "dvb/dvbs2arm_1v30.S"
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: read / write data
@:
@: Note: read only data tables are located near bottom of this file
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

 .text

 .ltorg @: literal pool

 .data

    .align 8 @: 256 byte boundary
frame: .space (16200 / 8) * 2 @: the frame is built up here
                 @: it doesn't need to be this big, but some of the LDPC
                 @: . . . routines overrun the end
    .align 2

output_loop_counter: .word 0 @: the number of times to go around the IQ output loop
datafield_overflow_count: .word 0 @: number of bytes that won't fit into the current frame
outbuffer_number: .word 0 @: number of the outbuffer currently in use (0-3)
outbuffer_base: .word 0 @: the base address of the buffer area, supplied by the calling program
                                                                @: ... should be at least 8832 bytes (4 * 4 * 552) on a 32 byte boundary

dvb_mode: .word 0
fec: .word 0 @: e.g 0x34 = 3/4, 0x3245 = 32/45
datafield_size: .word 0 @: number of bytes in the datafield
datafield_start_pointer: .word 0 @: pointer to the start of the datafield
datafield_current_pointer: .word 0 @: pointer to the next free byte in the datafield
bbframe_size: .word 0 @: number of bytes in the bbframe
bbheader_rolloff: .word 0 @: 0x20, 0x25, 0x35
bchbytes_pointer: .word 0 @: pointer to the BCH bytes in the frame
ldpc_size: .word 0 @: number of LDPC bytes in the frame
ldpc_parameters_pointer: .word 0 @: LPDC parameters table
ldpc_pointer: .word 0 @: pointer to the start of the LDPC bytes in the frame
ldpc_reformat_routine: .word 0 @: address of the LDPC reformat routine
efficiency: .word 0 @: required incoming TS rate = efficiency * SR / 1000000

 .align 8
overflow_buffer: .space 188 @: datafield overflow bytes are saved here
 .align 8
ldpc_inter_array: .space 40 * 64 @: intermediate output array when applying the LDPC parameters

 .text

 .ltorg @: literal pool

 .align 2 @: 4 byte boundary

@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: _dvbs2arm_control
@:
@: Calling from C:
@: uint32 _dvbs2arm_control (uint32 command, uint32 param1) ;
@:
@: Accepts a command and parameter
@:
@: command name command parameter return (0 = error)
@: ---------------------------------------------------------------------------------
@: 1 1 buffer address version
@: 2 2 0x14, 0x34 parameter value
@: 3 3 0x20, 0x25, 0x35 parameter value
@: 4 4 none decimal value
@:
@: When setting the mode, FEC 3/4 and rolloff 0.35 are selected as defaults
@:
@: The supplied buffer address should point to 8832 bytes on a 32 byte boundary (not checked)
@: This area is used to cycle around 4 x 2208 byte output buffers
@: It is usually in non-cached ram used for DMA
@: Buffer address = 0 selects DVB-S mode (for future development)
@:
@: Version 12.34 would be returned as 0x00001234
@:
@: The effiency value is used to determine the required bit rate of the 188 byte TS
@: Bit rate = symbol_rate * efficiency / 1,000,000
@:
@: Typical usage:
@:
@: _dvbs2arm_control (1,&buffer) ;
@: _dvbs2arm_control (2,0x34) ;
@: _dvbs2arm_control (3,0x35) ;
@: while (1)
@: {
@: PWMbuffer = _dvbs2arm_process_packet (&packet188) ;
@: if (PWMbuffer)
@: {
@: transmit_IQ (PWMbuffer) ;
@: PWMbuffer = 0 ;
@: }
@: } ;
@:
@: DVB-S functions may be added to this program in the future
@;
@: All registers except r0 are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

_dvbs2arm_control:
 push {r4,r5,r14}
    mov r4,r0 @: move command to r4

 teq r4,#1
 beq control_set_mode

 teq r4,#2
 beq control_set_fec

    teq r4,#3
 beq control_set_rolloff

 teq r4,#4
 beq control_get_efficiency

 mov r0,#0
 b control_exit @: error


control_set_mode:
 teq r1,#0 @: if buffer address = zero, this sets DVB-S mode (in the future)
    beq control_set_mode_dvbs

@: DVB-S2 mode

 ldr r4,=dvb_mode
 ldr r5,=2
    str r5,[r4] @: save the DVB mode
    ldr r4,=outbuffer_base
    str r1,[r4] @: save the outbuffer base address
 bl setup_s34 @: default to FEC 3/4
    ldr r4,=bbheader_rolloff
    ldr r5,=0x35 @: default value
    str r5,[r4]
 b csm2 @: return with version number

control_set_mode_dvbs:
 ldr r4,=dvb_mode @: save the DVB mode
    ldr r5,=1
 str r5,[r4]
csm2:
    ldr r0,=0x130 @: v1.30 @: success - return the version number
 b control_exit

control_set_fec:
 teq r1,#0x14
 beq control_set_fec_14
 teq r1,#0x34
 beq control_set_fec_34
 mov r0,#0 @: error
 b control_exit

control_set_fec_14:
 bl setup_s14
 mov r0,r1 @: return the parameter value
 b control_exit

control_set_fec_34:
 bl setup_s34
 mov r0,r1 @: return the parameter value
 b control_exit

control_set_rolloff:
    mov r5,r1 @: rolloff parameter
    teq r5,#0x20
    beq csr2
    teq r5,#0x25
    beq csr2
    teq r5,#0x35
    beq csr2
    mov r0,#0
    b control_exit @: error - must be 0x20, 0x25, 0x35
csr2:
    ldr r5,=bbheader_rolloff
    str r1,[r5] @: save the parameter
    mov r0,r1 @: return the parameter value
    b control_exit

control_get_efficiency:
 ldr r5,=efficiency
 ldr r0,[r5]
 b control_exit

control_exit:
 pop {r4,r5,r14}
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: set up for FEC 1/4
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

setup_s14:
 push {r4,r5,r6}

 ldr r6,=fec
 ldr r4,=0x14
 str r4,[r6]

 ldr r6,=outbuffer_number
 mov r4,#0
 str r4,[r6] @: save as the current outbuffer number (1 of 4)

 ldr r6,=datafield_overflow_count
 mov r4,#0
 str r4,[r6] @: clear the datafield overflow count

 ldr r4,=frame
 ldr r5,=10
 add r4,r5
 ldr r6,=datafield_start_pointer @: save the pointer to the start of the datafield
 str r4,[r6]

 ldr r6,=datafield_current_pointer @: set to the start of the datafield
 str r4,[r6]

 ldr r5,=(3072 / 8)
 ldr r6,=bbframe_size
 str r5,[r6] @: save the BB frame size

 ldr r5,=((3072 / 8)-10)
 ldr r6,=datafield_size
 str r5,[r6] @: save the datafield size

 add r4,r5
 ldr r6,=bchbytes_pointer
 str r4,[r6] @: save the pointer to the BCH bytes in the frame

 ldr r5,=21
 add r4,r5
 ldr r6,=ldpc_pointer
 str r4,[r6] @: save the pointer to the LDPC bytes in the frame

 ldr r4,=(12960 / 8)
 ldr r6,=ldpc_size
 str r4,[r6] @: save the number of LDPC bytes that are in the frame

 ldr r4,=ldpc_parameters_s14
 ldr r6,=ldpc_parameters_pointer @: save the pointer to the LDPC parameters for this FEC
 str r4,[r6]

 ldr r4,=ldpc_reformat_s14
 ldr r6,=ldpc_reformat_routine
 str r4,[r6] @: save the address of the routine that rebuilds the LDPC bytes

 ldr r4,=365323
 ldr r6,=efficiency
 str r4,[r6] @: save the efficiency factor

 pop {r4,r5,r6}
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: set up for FEC 3/4
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

setup_s34:
 push {r4,r5,r6}

 ldr r6,=fec
 ldr r4,=0x34
 str r4,[r6]

 ldr r6,=outbuffer_number
 mov r4,#0
 str r4,[r6] @: save as the current outbuffer number (1 of 4)

 ldr r6,=datafield_overflow_count
 mov r4,#0
 str r4,[r6] @: clear the datafield overflow count

 ldr r4,=frame
 ldr r5,=10
 add r4,r5
 ldr r6,=datafield_start_pointer
 str r4,[r6]

 ldr r6,=datafield_current_pointer
 str r4,[r6]

 ldr r5,=(11712 / 8)
 ldr r6,=bbframe_size
 str r5,[r6]

 ldr r5,=((11712 / 8)-10)
 ldr r6,=datafield_size
 str r5,[r6]

 add r4,r5
 ldr r6,=bchbytes_pointer
 str r4,[r6]

 ldr r5,=21
 add r4,r5
 ldr r6,=ldpc_pointer
 str r4,[r6]

 ldr r4,=(4320 / 8)
 ldr r6,=ldpc_size
 str r4,[r6]

 ldr r4,=ldpc_parameters_s34
 ldr r6,=ldpc_parameters_pointer
 str r4,[r6]

 ldr r4,=ldpc_reformat_s34
 ldr r6,=ldpc_reformat_routine
 str r4,[r6]

 ldr r4,=1420268
 ldr r6,=efficiency
 str r4,[r6]

 pop {r4,r5,r6}
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: _dvbs2arm_process_packet
@:
@: Adds a packet to the datafield and returns a pointer to an IQ buffer when a frame is ready
@:
@: Calling from C:
@: uchar* _dvbs2arm_process_packet (uchar *packet188) ;
@:
@: Accepts the address of a 188 byte packet starting with 0x47 (not checked)
@:
@: Returns a status indication or a pointer to an IQ buffer for PWM transmission
@: 0 = more packets are required to fill the frame
@: !0 = pointer to a 546 word IQ buffer containing a short frame
@:
@: 4 outbuffers are used in sequence so that it is not neccessary to move the
@: data to prevent it being overwritten by the next frame
@:
@: All registers except r0 are restored to their original values
@:
@: The output IQ buffer is formatted so that its address can be directly used for PWM DMA
@: PWM.RNG1 and PWM.RNG2 should both be set to 30 to send only bits 31-2
@:
@: Output buffer format:
@: 546 x 32 bit words
@: even words contain 30 I bits bit 31 is transmitted first
@: odd words contain 30 Q bits bit 31 is transmitted first
@:
@: word 0: IIIIIIIIIIIIIIIIIIIIIIIIIIIIII..
@: word 1: QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ..
@: . . . . .
@: word 544: IIIIIIIIIIIIIIIIIIIIIIIIIIIIII..
@: word 545: QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ..
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

_dvbs2arm_process_packet:
 push {r1-r7,r14}

 ldr r1,=datafield_current_pointer
 ldr r2,[r1] @: current pointer to the datafield
 mov r1,#187
 add r0,#1 @: process 187 bytes, but not the leading sync byte
 bl calculate_crc8_and_optionally_move @: copy the packet into the datafield and return the CRC8

 ldr r1,=datafield_current_pointer
 ldr r2,[r1] @: current pointer to the datafield
 add r2,#187 @: 187 bytes have been added to the datafield
 strb r0,[r2],#1 @: add the returned CRC8 to the datafield and move to the next byte
 str r2,[r1] @: save the updated datafield pointer

 ldr r3,=bchbytes_pointer
 ldr r3,[r3] @: r3 points to just past the end of the datafield in the frame
 mov r0,#0 @: return zero if frame not ready
 subs r2,r3 @: datafield pointer minus end of datafield
 blt dap4 @: there is still room in the datafield - wait for next packet
             @: r2 contains the number of bytes overflowing the datafield

@: datafield is full - move the overflow bytes to a temporary buffer

 ldr r3,=bchbytes_pointer
 ldr r3,[r3] @: r3 points to the overflow bytes past the end of the datafield in the frame
 ldr r4,=overflow_buffer @: pointer to the temporary overflow buffer
 mov r5,r2 @: number of overflow bytes for this frame
 teq r5,#0
 beq dap2a @: no overflow bytes
dap2:
 ldrb r7,[r3],#1 @: read an overflow byte and advance to next
 adds r5,#-1 @: decrement the loop counter
 strb r7,[r4],#1 @: store the byte to the overflow buffer and advance to next
 bne dap2 @: go around the loop
dap2a:

 ldr r0,=frame
 bl add_bb_header @: add the 10 byte BB header to the front of the datafield

 ldr r6,=datafield_overflow_count
 str r2,[r6] @: save the number of overflow bytes for this frame

 ldr r0,=frame
 bl process_bbframe @: do the rest of the required processing on the BB frame
             @: the returned value of r0 points to the output buffer

@: move the overflow bytes to the start of the new datafield

 ldr r3,=overflow_buffer @: pointer to the temporary overflow buffer
 ldr r4,=datafield_start_pointer
 ldr r4,[r4] @: pointer to the start of the datafield
 ldr r5,[r6] @: number of overflow bytes for this frame
 teq r5,#0
 beq dap3a @: no overflow bytes
dap3:
 ldrb r7,[r3],#1 @: read an overflow byte and advance to next
 adds r5,#-1 @: decrement the loop counter
 strb r7,[r4],#1 @: store it to the start of the new datafield
 bne dap3
dap3a:

 ldr r3,=datafield_current_pointer
 str r4,[r3] @: save the new datafield pointer

@: select the next PWM output buffer

 ldr r3,=outbuffer_number
 ldr r4,[r3] @: number of the current outbuffer
 add r4,#1 @: increment the outbuffer number
 and r4,#3 @: 4 outbuffers
 str r4,[r3] @: save the new outbuffer number
             @: return with r0 pointing to the outbuffer containing the frame
dap4:
 pop {r1-r7,r14}
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: add_bb_header
@: the 10 byte BB header is added to the front of the datafield
@: this is now a BB frame
@:
@: Calling:
@: r0 points to the frame (start of BB header)
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

add_bb_header:
 push {r0-r6,r14}
 mov r3,r0 @: r3 is now the frame pointer

 ldr r4,=bbheader_rolloff
 ldr r4,[r4]

    ldr r5,=0 @: default rolloff value 0.35
    teq r4,#0x25
    ldreq r5,=1
    teq r4,#0x20
    ldreq r5,=2

 add r5,#0xf0 @: transport stream, single TS, CCM, no ISSY, no NPD
 strb r5,[r3],#1 @: store the byte into the header

 mov r4,#0 @: this header byte is not used
 strb r4,[r3],#1

 ldr r5,=188 * 8 @: number of bits in a packet
 mov r4,r5,lsr #8 @: upper byte
 strb r4,[r3],#1
 and r4,r5,#0xff @: lower byte
 strb r4,[r3],#1

 ldr r5,=datafield_size
 ldr r5,[r5] @: number of bytes in the datafield
 lsl r5,#3 @: convert to number of bits
 mov r4,r5,lsr #8 @: upper byte
 strb r4,[r3],#1
 and r4,r5,#0xff @: lower byte
 strb r4,[r3],#1

 mov r4,#0x47 @: sync byte value
 strb r4,[r3],#1

@: calculate and store the bit offset from the start of the datafield of the first CRC8 byte

 ldr r6,=datafield_overflow_count
 ldr r5,[r6] @: get the number of bytes overflowing the datafield in the previous frame
 adds r5,#-1 @: account for the removed 0x47 transport stream sync byte
 addlt r5,#188 @: add 188 if negative
 lsl r5,#3 @: convert to a number of bits
 mov r4,r5,lsr #8 @: upper byte
 strb r4,[r3],#1
 and r4,r5,#0xff @: lower byte
 strb r4,[r3],#1

 ldr r0,=frame @: base address of the frame (start of BB header)
 mov r1,#9 @: number of bytes to process in the BB header
 mov r2,#0 @: do not move the bytes anywhere
 bl calculate_crc8_and_optionally_move @: generate the CRC8 for the BB header
 strb r0,[r3],#1 @: store the CRC8 into the BB header

 pop {r0-r6,r14}
 mov pc,r14 @: return


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: process_bbframe:
@ performs BB scramble, BCH, LDPC, PL header, symbols scramble, IQ split
@:
@: Calling:
@: r0 points to the BB frame
@:
@: Return:
@: r0 is the address of the outbuffer
@:
@: All registers except r0 are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

process_bbframe:
 push {r1-r4,r14}

 push {r0}
 ldr r1,=bbframe_size
 ldr r1,[r1]
 bl bbframe_scramble @: apply the BB frame scrambling
 pop {r0}

 push {r0}
 ldr r1,=bbframe_size
 ldr r1,[r1] @: number of bytes in the BB frame
 bl bch_encode @: append the BCH bytes to the BB frame, producing a BCH frame
 pop {r0}

 push {r0}
 mov r1,r0 @: pointer to the BCH frame
 ldr r0,=ldpc_parameters_pointer
 ldr r0,[r0]
 bl ldpcs_encode @: append the LDPC bytes to the BCH frame
 pop {r0}

 ldr r2,=outbuffer_number
 ldr r3,[r2] @: number of the current outbuffer (0-3)
    ldr r4,=2208
    mul r3,r4 @: 1 of 4 x 2208 byte buffers
 ldr r2,=outbuffer_base
    ldr r4,[r2] @: address of the supplied buffer area
    add r1,r3,r4 @: address of the current outbuffer
 push {r1} @: save the address of the outbuffer

@: put the PL header into the IQ outbuffer

 ldr r3,=fec
    ldr r3,[r3] @: get the FEC
 ldr r2,=PL_HEADER_S34_IQ @: default to FEC 3/4
 teq r3,#0x14
 ldreq r2,=PL_HEADER_S14_IQ @: FEC 1/4
 mov r3,#6 @: word count
dpb2: @: move the header to the outbuffer
 ldr r4,[r2],#4 @: get a PL header word
 adds r3,#-1 @: decrement the loop count
 str r4,[r1],#4 @: store into the outbuffer
 bne dpb2

@: scramble the frame and split into IQ words in the outbuffer

 bl symbols_scramble_and_split @: r0 points to the frame, r1 points to the outbuffer just past the PL header
 pop {r0} @: restore the address of the outbuffer, for the return value

 pop {r1-r4,r14}
 mov pc,r14 @: return


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: calculate_crc8_and_optionally_move
@:
@: Calling:
@: r0 points to the input buffer to be processed
@: r1 is the number of bytes to be processed
@: r2 is the address where the input buffer should be copied
@: r2 = zero if copying is not required
@:
@: Return:
@: r0 is the calculated CRC8 value
@:
@: All registers except r0 are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

calculate_crc8_and_optionally_move:
 push {r1,r2,r3,r4,r5}
 ldr r5,=crc8_table
 mov r3,#0 @: acumulator
crc2:
 ldrb r4,[r0],#1 @: get a byte from the input buffer
 eor r3,r4 @: xor into the accumulator
 ldrb r3,[r5,r3] @: get the new accumulator from the CRC8 table
 teq r2,#0 @: check if we need to write the input byte to an output buffer
 strneb r4,[r2],#1 @: store input byte to the output buffer and move to next
 adds r1,#-1 @: decrement byte count
 bne crc2 @: go around the loop
crc4:
 mov r0,r3 @: return the accumulator
 pop {r1,r2,r3,r4,r5}
 mov pc,r14 @: return


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: bbframe_scramble
@:
@: each byte of the BB frame is XORed with a byte from bbframe_scramble_table
@:
@: Calling:
@: r0 points to the start of the BB frame
@: r1 is the number of bytes in the BB frame to process
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

bbframe_scramble:
 push {r0,r1,r2,r3,r4}
 lsr r1,#2 @: change the byte count to a word count
 ldr r2,=bbframe_scramble_table
bbs2:
 ldr r3,[r0] @: get 4 bytes from the input buffer
 ldr r4,[r2],#4 @: get 4 bytes from the scramble table and move to next word
 adds r1,#-1 @: decrement the word count
 eor r3,r4 @: XOR with the buffer word
 str r3,[r0],#4 @: save it back to the buffer
 bne bbs2 @: go around the loop
 pop {r0,r1,r2,r3,r4}
 mov pc,r14 @: return


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: bch_encode
@: calculate the 21 BCH bytes and add to the end of the BB frame
@: this is now a BCH frame
@:
@: Calling:
@: r0 points to the start of the BB frame
@: r1 is the number of bytes in the BB frame to process
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

bch_encode:
 push {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12}

 mov r6,r0 @: r6 will be input buffer pointer
 mov r12,r1 @: r12 is the count of bytes to be processed
 add r7,r0,r1 @: r7 will be the output pointer, appending to the BB frame

 mov r0,#0 @: initialise the BCH bytes shift buffer
 mov r1,#0
 mov r2,#0
 mov r3,#0
 mov r4,#0
 mov r5,#0

 ldr r9,=bch_s168_table @: 168 bits (21 bytes) will be added

bch2: @: r12 is the input byte loop counter
 ldrb r11,[r6],#1 @: get an input byte and advance to next
 eor r11,r0 @: XOR in the most significant BCH byte
 add r10,r9,r11,lsl #5 @: multiply by 32 and add to the bch_s168_table start address

          @: move the 6 words of the shift buffer left by 1 byte
 ldr r11,[r10],#4 @: get a word from table2
 mov r0,r1,lsr #24
 eor r0,r11 @: XOR into the 21 byte shift buffer

 lsl r1,#8
 ldr r11,[r10],#4
 orr r1,r2,lsr #24
 eor r1,r11

 lsl r2,#8
 ldr r11,[r10],#4
 orr r2,r3,lsr #24
 eor r2,r11

 lsl r3,#8
 ldr r11,[r10],#4
 orr r3,r4,lsr #24
 eor r3,r11

 lsl r4,#8
 ldr r11,[r10],#4
 orr r4,r5,lsr #24
 eor r4,r11

 lsl r5,#8
 ldr r11,[r10],#4
 eor r5,r11

 adds r12,#-1 @: input byte count
 bne bch2

 strb r0,[r7],#1 @: store the most significant byte of the BCH shift buffer - r7 is output pointer
 rev r1,r1
 str r1,[r7],#4 @: and the 4 following words with byte order reversed - ms byte is first in order in the output byte array
 rev r2,r2
 str r2,[r7],#4
 rev r3,r3
 str r3,[r7],#4
 rev r4,r4
 str r4,[r7],#4
 rev r5,r5
 str r5,[r7],#4

bch98:
 pop {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12}
 mov pc,r14

 .ltorg @: literal pool


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: ldpcs_encode
@: adds the LDPC bytes to the end of the BCH frame
@: this is now a FEC frame
@:
@: Calling:
@: r0 points to the LDPC parameters table
@: r1 points to the BCH frame
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

ldpcs_encode:
 push {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r14}

 ldr r6,=ldpc_inter_array @: intermediate LDPC output area
 mov r7,#0
 ldr r8,=(40 * 64 / 4) @: number of intermediate LDPC words to clear
ldpcs1:
 str r7,[r6],#4 @: clear the area
 adds r8,#-1
 bne ldpcs1

ldpcs2: @: loop here for each entry in the LDPC parameters table
 push {r1,r2} @: push @: save the calling parameters
 ldr r5,[r0],#4 @: r0 points to the parameters line - load 5 words from update r0 for next line
 ldr r6,[r0],#4 @: r6 is the offset to the BCH frame input byte group (45 bytes)
 ldr r7,[r0],#4 @: r7 is the offset of the LDPC intermediate output byte array row
 ldr r8,[r0],#4 @: r8 is the shift left value for the first register
 ldr r9,[r0],#4 @: r9 is the routine to handle the particular start register (r0-r11)

 adds r5,#1 @: check for end of table (LDPC parameter bit number - unused)
 beq ldpcs4 @: was -1, so end of list
 push {r0} @: push @: save the LDPC parameters pointer for later
 add r5,#-1

 add r0,r6,r1 @: r0 is now the address of the BCH frame input group (45 bytes)

 push {r8} @: push @: save the shift left value for later
 ldr r10,=ldpc_inter_array
 add r10,r7 @: r10 is now the address of the LDPC intermediate output byte array row
 push {r10} @: push @: save the intermediate LDPC row address for later
 blx r9 @: call the routine

 pop {r14} @: pull @: r14 is the pointer to the intermediate LDPC output array row
 pop {r12} @: pull @: r12 is the first shift left value

@: apply the BCH group to the LDPC row






 push {r7,r8,r9} @: save the temporary registers

 rsb r7,r12,#32 @: r7 = 32 - r12 number of bits to shift right second register

 mov r8,r0,lsl r12 @: shift the first register
 ldr r9,[r14] @: get a word from the LDPC output array
 orr r8,r1,lsr r7 @: orr in the shifted second register
 eor r9,r8 @: merge
 str r9,[r14],#4 @: save back into LDPC output array and move to next word

 mov r8,r1,lsl r12 @: shift the first register
 ldr r9,[r14] @: get a word from the LDPC output array
 orr r8,r2,lsr r7 @: orr in the shifted second register
 eor r9,r8 @: merge
 str r9,[r14],#4 @: save back into LDPC output array and move to next word

 mov r8,r2,lsl r12 @: shift the first register
 ldr r9,[r14] @: get a word from the LDPC output array
 orr r8,r3,lsr r7 @: orr in the shifted second register
 eor r9,r8 @: merge
 str r9,[r14],#4 @: save back into LDPC output array and move to next word

 mov r8,r3,lsl r12 @: shift the first register
 ldr r9,[r14] @: get a word from the LDPC output array
 orr r8,r4,lsr r7 @: orr in the shifted second register
 eor r9,r8 @: merge
 str r9,[r14],#4 @: save back into LDPC output array and move to next word

 mov r8,r4,lsl r12 @: shift the first register
 ldr r9,[r14] @: get a word from the LDPC output array
 orr r8,r5,lsr r7 @: orr in the shifted second register
 eor r9,r8 @: merge
 str r9,[r14],#4 @: save back into LDPC output array and move to next word

 mov r8,r5,lsl r12 @: shift the first register
 ldr r9,[r14] @: get a word from the LDPC output array
 orr r8,r6,lsr r7 @: orr in the shifted second register
 eor r9,r8 @: merge
 str r9,[r14],#4 @: save back into LDPC output array and move to next word

 pop {r7,r8,r9} @: restore current temporary registers
# 961 "dvb/dvbs2arm_1v30.S"
 push {r1,r2,r3} @: save the temporary registers

 rsb r1,r12,#32 @: r1 = 32 - r12, number of bits to shift right second register

 mov r2,r6,lsl r12 @: shift the first register
 ldr r3,[r14] @: get a word from the LDPC output array
 orr r2,r7,lsr r1 @: orr in the shifted second register
 eor r3,r2 @: merge
 str r3,[r14],#4 @: save back into LDPC output array and move to next word

 mov r2,r7,lsl r12 @: shift the first register
 ldr r3,[r14] @: get a word from the LDPC output array
 orr r2,r8,lsr r1 @: orr in the shifted second register
 eor r3,r2 @: merge
 str r3,[r14],#4 @: save back into LDPC output array and move to next word

 mov r2,r8,lsl r12 @: shift the first register
 ldr r3,[r14] @: get a word from the LDPC output array
 orr r2,r9,lsr r1 @: orr in the shifted second register
 eor r3,r2 @: merge
 str r3,[r14],#4 @: save back into LDPC output array and move to next word

 mov r2,r9,lsl r12 @: shift the first register
 ldr r3,[r14] @: get a word from the LDPC output array
 orr r2,r10,lsr r1 @: orr in the shifted second register
 eor r3,r2 @: merge
 str r3,[r14],#4 @: save back into LDPC output array and move to next word

 mov r2,r10,lsl r12 @: shift the first register
 ldr r3,[r14] @: get a word from the LDPC output array
 orr r2,r11,lsr r1 @: orr in the shifted second register
 eor r3,r2 @: merge
 str r3,[r14],#4 @: save back into LDPC output array and move to next word

 mov r2,r11,lsl r12 @: shift the first register
 mov r3,r0,lsl #24
 orr r2,r3,lsr r1 @: orr in the shifted second register
 ldr r3,[r14] @: get a word from the LDPC output array
 eor r3,r2 @: merge
 and r3,#0xff000000
 str r3,[r14],#4 @: save back into LDPC output array and move to next word

 pop {r1,r2,r3} @: restore current temporary registers





 pop {r0} @: pull @: restore the parameters pointer
 pop {r1,r2} @: pull @: restore the calling parameters

 b ldpcs2 @: process the next line of the LDPC parameters table

 pop {r1,r2} @: pull @: restore calling parameters

@: parameters table processing complete
@: now convert the LDPC intermediate output byte array to the correct format and append to the BCH frame

ldpcs4:
 pop {r1,r2} @: pull @: restore calling parameters
 ldr r0,=ldpc_pointer
 ldr r0,[r0] @: r0 points to the LDPC bytes start position in the frame
    ldr r5,=ldpc_reformat_routine
    ldr r5,[r5] @: r5 is the address of the reformat routine
 blx r5 @: convert back to linear byte format



ldpcs12:
 ldr r5,=ldpc_xor_table
 ldr r6,=ldpc_pointer
 ldr r6,[r6] @: r6 points to the LDPC bytes start position in the frame
    ldr r7,=ldpc_size @: number of LDPC bytes in the frame
    ldr r7,[r7] @: number of LDPC bytes for this FEC
 ldr r8,=0x1ff @: masking constant
 mov r9,#0 @: previous output value
ldpcs14:
 ldrb r10,[r6] @: get a byte from the output array
 orr r10,r9,lsl #8 @: move the previous output byte to the upper byte
 and r10,r8 @: mask off 9 bits
 ldrb r11,[r10,r5] @: get a byte from the conversion table
 adds r7,#-1 @: decrement the loop counter
 strb r11,[r6],#1 @: save the converted byte back to the output array
 mov r9,r11 @: save it as the previous output
 bne ldpcs14 @: go around the loop again

ldpcs16:
 pop {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r14}
 mov pc,lr @: return


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: ldpc_reformat_s14
@: convert the ldpc intermediate array and append to the end of the BCH frame
@: this is now a FEC frame
@:
@: Calling:
@: r0 is an output pointer to the LDPC bytes start position in the frame
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

ldpc_reformat_s14:
 push {r0-r12,r14}

@: clear the LDPC bytes in the frame

    ldr r4,=ldpc_pointer
 ldr r4,[r4] @: r4 is the output pointer to the LDPC bytes in the frame
    ldr r5,=ldpc_size
 ldr r5,[r5] @: number of LDPC bytes in the frame
 lsr r5,#2 @: word count
    mov r6,#0
ldpc14s2:
    str r6,[r4],#4
    adds r5,#-1
    bne ldpc14s2

    mov r14,r0 @: r14 will be used as the output pointer to the LDPC area in the frame
 ldr r12,=ldpc_inter_array @: r12 is an input pointer to the LDPC intermediate array

@: outer loop -------------------------- @: 12 iterations horizontally, covering 48 bytes (only 45 used)

    mov r9,#0 @: outer loop counter
ldpc14s6:
 push {r12} @: save the input pointer
 push {r14} @: save the output pointer

@: middle loop ------------------------- @: 5 iterations vertically, covering 8 rows of 40 (only 36 needed)

 mov r10,#0 @: middle loop counter
ldpc14s7:
 ldr r0,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r1,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r2,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r3,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r4,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r5,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r6,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r7,[r12],#64 @: load register and step on 64 bytes to the next row
 push {r12} @: save the input pointer
 push {r14} @: save the output pointer

@: inner loop --------------------------- @: 16 iterations processing 8 x 32 bits, 2 bits at a time

    mov r11,#0 @: inner loop counter
ldpc14s8:
    mov r12,#0 @: r12 will be used as the output register, r14 is the output pointer
    lsls r0,#1
    adcs r12,r12,r12 @: = rlx #1
    lsls r1,#1
    adcs r12,r12,r12
    lsls r2,#1
    adcs r12,r12,r12
    lsls r3,#1
    adcs r12,r12,r12
    lsls r4,#1
    adcs r12,r12,r12
    lsls r5,#1
    adcs r12,r12,r12
    lsls r6,#1
    adcs r12,r12,r12
    lsls r7,#1
    adcs r12,r12,r12
 ldrb r8,[r14,#0]
 orr r12,r8
    strb r12,[r14,#0] @: store complete byte 0 and move to byte 4: 0, 9, 13

    mov r12,#0
    lsls r0,#1
    adcs r12,r12,r12
    lsls r1,#1
    adcs r12,r12,r12
    lsls r2,#1
    adcs r12,r12,r12
    lsls r3,#1
    adcs r12,r12,r12
    ldrb r8,[r14,#4]
    orr r12,r8
    strb r12,[r14,#4] @: add the lower half of byte 4 and move to byte 5: 4, 13, 22

    mov r12,#0
    lsls r4,#1
    adcs r12,r12,r12
    lsls r5,#1
    adcs r12,r12,r12
    lsls r6,#1
    adcs r12,r12,r12
    lsls r7,#1
    adcs r12,r12,r12
    ldrb r8,[r14,#5]
    lsl r12,#4
    orr r12,r8
    strb r12,[r14,#5] @: add the upper half of byte 5 and move to byte 9: 5, 14, 23

 add r14,#9 @: increment the output pointer

    adds r11,#1
    teq r11,#16
    bne ldpc14s8 @: ---------------- @: go around the inner loop 16 times, 2 shifts per word per loop

 pop {r14} @: restore the output pointer
 add r14,#1 @:
 pop {r12} @: restore the input pointer

 adds r10,#1
 teq r10,#5
 bne ldpc14s7 @: ---------------- @: go around the middle loop 5 times

    pop {r14} @: restore the output pointer
    pop {r12} @: restore the input pointer
    add r12,#4 @: move the input pointer to the next column of 32 bit words
    add r14,#144 @: move the output pointer to the next 144 output bytes

    adds r9,#1
    teq r9,#12
    bne ldpc14s6 @: ---------------- @: go around the outer loop 12 times

   pop {r0-r12,r14}
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: ldpc_reformat_s34
@: convert the ldpc intermediate array and append to the end of the BCH frame
@: this is now a FEC frame
@:
@: Calling:
@: r0 is a pointer to the LDPC bytes start position in the frame
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

ldpc_reformat_s34:
 push {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r14}

    mov r14,r0 @: r14 will be used as the pointer to the LDPC bytes in the frame
 ldr r12,=ldpc_inter_array @: r12 is a pointer to the LDPC intermediate array

 ldr r0,=output_loop_counter
 mov r1,#11 @: 11 major loops
 str r1,[r0] @: reset the output loop counter

ldpcs6:
 push {r12} @: save the input pointer

 ldr r0,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r1,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r2,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r3,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r4,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r5,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r6,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r7,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r8,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r9,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r10,[r12],#64 @: load register and step on 64 bytes to the next row
 ldr r11,[r12],#64 @: load register and step on 64 bytes to the next row



 push {r14} @: save output pointer
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_8_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12 @: bit 31 is most significant before the reverse
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_4_bits_starting_at_8
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_4_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_8_bits_starting_at_4
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next

 ldr r12,=output_loop_counter
 ldr r12,[r12]
 teq r12,#0
 bne ldpcs8
 pop {r12} @: restore the input pointer
 b ldpcs10

ldpcs8:

 @: end of loop



 push {r14} @: save output pointer
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_8_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_4_bits_starting_at_8
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_4_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_8_bits_starting_at_4
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next



 push {r14} @: save output pointer
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_8_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_4_bits_starting_at_8
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_4_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_8_bits_starting_at_4
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next



 push {r14} @: save output pointer
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_8_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_4_bits_starting_at_8
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 bl do_4_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next
 push {r14} @: save output pointer
 bl do_8_bits_starting_at_4
 bl do_12_bits_starting_at_0
 bl do_12_bits_starting_at_0
 pop {r14} @: restore output pointer
 rev r12,r12
 str r12,[r14],#4 @: save the output word and point to next



 pop {r12} @: restore input pointer
 add r12,#4 @: move to the next word in the first row of the LDPC intermediate output byte array

 ldr r6,=output_loop_counter
 ldr r7,[r6]
 add r7,#-1
 str r7,[r6]
 b ldpcs6 @: go round the loop again - loop termination check is after the first 3 of 12

ldpcs10:
 pop {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r14}
 mov pc,lr @: return


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: LDPC0first
@: these 12 routines are used by ldpcs_encode to rotate the BCH input group
@: the routine used depends on the LDPC parameters
@:
@: Calling:
@: r0 is a pointer to the BCH frame input group (45 bytes, 360 bits)
@:
@: Registers are NOT restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

LDPC0first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}

 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11
 and r11,#0xff000000
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 orr r11,r12,lsr #8
 mov pc,r14

LDPC1first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r11,[r12],#4
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 rev r10,r10
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r10,#0xff000000
 orr r10,r12,lsr #8
 mov pc,r14

LDPC2first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r10,[r12],#4
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 rev r9,r9
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r9,#0xff000000
 orr r9,r12,lsr #8
 mov pc,r14

LDPC3first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r9,[r12],#4
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 rev r8,r8
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r8,#0xff000000
 orr r8,r12,lsr #8
 mov pc,r14

LDPC4first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r8,[r12],#4
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 rev r7,r7
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r7,#0xff000000
 orr r7,r12,lsr #8
 mov pc,r14

LDPC5first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r7,[r12],#4
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 rev r6,r6
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r6,#0xff000000
 orr r6,r12,lsr #8
 mov pc,r14

LDPC6first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r6,[r12],#4
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 rev r5,r5
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r5,#0xff000000
 orr r5,r12,lsr #8
 mov pc,r14

LDPC7first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r5,[r12],#4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 rev r4,r4
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r4,#0xff000000
 orr r4,r12,lsr #8
 mov pc,r14

LDPC8first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r4,[r12],#4
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 rev r3,r3
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r3,#0xff000000
 orr r3,r12,lsr #8
 mov pc,r14

LDPC9first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r3,[r12],#4
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 ldr r2,[r12],#4
 rev r1,r1
 rev r2,r2
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r2,#0xff000000
 orr r2,r12,lsr #8
 mov pc,r14

LDPC10first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r2,[r12],#4
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 ldr r1,[r12],#4
 rev r0,r0
 rev r1,r1
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r1,#0xff000000
 orr r1,r12,lsr #8
 mov pc,r14

LDPC11first:
 mov r12,r0 @: r12 will be the pointer to the BCH frame input group
 push {r12}
 add r12,#3
 ldr r1,[r12],#4
 ldr r2,[r12],#4
 rev r1,r1
 ldr r3,[r12],#4
 rev r2,r2
 ldr r4,[r12],#4
 rev r3,r3
 ldr r5,[r12],#4
 rev r4,r4
 ldr r6,[r12],#4
 rev r5,r5
 ldr r7,[r12],#4
 rev r6,r6
 ldr r8,[r12],#4
 rev r7,r7
 ldr r9,[r12],#4
 rev r8,r8
 ldr r10,[r12],#4
 rev r9,r9
 ldr r11,[r12],#4
 rev r10,r10
 rev r11,r11

 add r12,#-3
 ldr r0,[r12],#4
 rev r0,r0
 pop {r12}
 ldr r12,[r12]
 rev r12,r12
 and r0,#0xff000000
 orr r0,r12,lsr #8

 and r11,#0xff000000 @: special fixup for r11
 orr r11,r0,lsr #8
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: do_12_bits_starting_at_0
@:
@: these routines are used to rebuild the LDPC bytes from the intermediate array
@:
@: shift a bit out of the top of 12 words in turn and form another word
@:
@: adcs r12,r12,r12 = rotate left with carry
@:
@: Calling:
@: r0-r11 contain a word from each row of ldpc_inter_table
@:
@: Registers are NOT restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

do_12_bits_starting_at_0:
 lsls r0,#1 @: shift the most significant bit into the carry
 adcs r12,r12,r12 @: = rlx, rotate the carry into bit 31
 lsls r1,#1
 adcs r12,r12,r12
 lsls r2,#1
 adcs r12,r12,r12
 lsls r3,#1
 adcs r12,r12,r12
 lsls r4,#1
 adcs r12,r12,r12
 lsls r5,#1
 adcs r12,r12,r12
 lsls r6,#1
 adcs r12,r12,r12
 lsls r7,#1
 adcs r12,r12,r12
 lsls r8,#1
 adcs r12,r12,r12
 lsls r9,#1
 adcs r12,r12,r12
 lsls r10,#1
 adcs r12,r12,r12
 lsls r11,#1
 adcs r12,r12,r12
 mov pc,r14

do_8_bits_starting_at_0:
 lsls r0,#1
 adcs r12,r12,r12
 lsls r1,#1
 adcs r12,r12,r12
 lsls r2,#1
 adcs r12,r12,r12
 lsls r3,#1
 adcs r12,r12,r12
 lsls r4,#1
 adcs r12,r12,r12
 lsls r5,#1
 adcs r12,r12,r12
 lsls r6,#1
 adcs r12,r12,r12
 lsls r7,#1
 adcs r12,r12,r12
 mov pc,r14

do_4_bits_starting_at_8:
 lsls r8,#1
 adcs r12,r12,r12
 lsls r9,#1
 adcs r12,r12,r12
 lsls r10,#1
 adcs r12,r12,r12
 lsls r11,#1
 adcs r12,r12,r12
 mov pc,r14

do_4_bits_starting_at_0:
 lsls r0,#1
 adcs r12,r12,r12
 lsls r1,#1
 adcs r12,r12,r12
 lsls r2,#1
 adcs r12,r12,r12
 lsls r3,#1
 adcs r12,r12,r12
 mov pc,r14

do_8_bits_starting_at_4:
 lsls r4,#1
 adcs r12,r12,r12
 lsls r5,#1
 adcs r12,r12,r12
 lsls r6,#1
 adcs r12,r12,r12
 lsls r7,#1
 adcs r12,r12,r12
 lsls r8,#1
 adcs r12,r12,r12
 lsls r9,#1
 adcs r12,r12,r12
 lsls r10,#1
 adcs r12,r12,r12
 lsls r11,#1
 adcs r12,r12,r12
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: symbols_scramble_and_split:
@: each IQ symbol is scrambled and stored as 30 bits I, 30 bits Q
@:
@: Calling:
@: r0 points to the FEC frame
@: r1 points to the output buffer
@:
@: All registers are restored to their original values
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

symbols_scramble_and_split:
 push {r0-r12}

 ldr r2,=(16200 / 8) @: number of input bytes to process: 2025 = 135 * 15
 mov r3,#0
 ldr r4,=symbols_scramble_table3
 ldr r5,=symbols_scramble_table4
    mov r6,#0 @: byte index and outer loop counter: 0-2024
sss2:
 mov r11,#0 @: clear I and Q words
 mov r12,#0
 mov r3,#0 @: counter for 15 byte inner loop
sss4:
    ldrb r7,[r4,r6] @: main symbols scramble table: 4 x 2 bits indicating scrambling type
 ldrb r8,[r0,r6] @: input byte from frame: 4 x 2 bits IQIQIQIQ

 and r9,r7,#0xf0 @: mask upper 4 bits of the scramble table
 orr r9,r8,lsr #4 @: concatenate with upper 4 bits of the frame byte
 ldrb r10,[r5,r9] @: get 4 scrambled output bits from the translation table ....IIQQ

 lsl r11,#2
 orr r11,r10,lsr #2 @: concatenate the 2 I bits at the low end of the output word
 lsl r12,#2
 and r10,#3
 orr r12,r10 @: concatenate the 2 Q bits at the low end of the output word

    and r9,r8,#0xf @: now process the lower 4 bits of the scramble and input bytes
    orr r9,r7,lsl #4
    and r9,#0xff
 ldrb r10,[r5,r9]

 lsl r11,#2
 orr r11,r10,lsr #2
 lsl r12,#2
 and r10,#3
 orr r12,r10

    add r3,#1 @: inner loop counter
 teq r3,#8
 beq sss4b @: at the mid point, 32 bits processed, but only 30 needed
 teq r3,#15
 bne sss5 @: not at the end point

@: output the I and Q registers

 lsl r11,#2 @: left shift at the end of 15 input bytes, but not at the midpoint
 lsl r12,#2
sss4b:
 str r11,[r1],#4 @: store I bits in the output buffer
 str r12,[r1],#4 @: store Q bits in the output buffer

@: clear the output words and leave the excess bits (2 x I, 2 x Q) from the previous output words, in case this is the midpoint

   and r11,#3 @: leave the 2 excess bits in each of the output registers
 and r12,#3 @: . . . in case this is the mid point

sss5:
    add r6,#1 @: increment the byte index: 0-2024
 teq r3,#15 @: inner loop counter
 bne sss4 @: go around the inner loop

sss6:
 teq r6,r2 @: compare byte index with bytes to be processed
 bne sss2 @: go around the outer loop
 pop {r0-r12}
 mov pc,r14

 .ltorg @: literal pool

.global _reverse_byte_order

_reverse_byte_order:
 rev r0,r0
 mov pc,r14


@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@:
@: Table data
@:
@:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

 .text

@: the PL header is formatted as 6 words: alternating 30 bits I, 30 bits Q, left justified

@: QPSK, FEC 3/4, short frame, no pilots

PL_HEADER_S34_IQ: .word 0x361EF5F4,0x634BA0A0,0xBC8D6630,0xE9D83364,0x1BA21EBC,0x4EF74BE8

@: QPSK, FEC 1/4, short frame, no pilots

PL_HEADER_S14_IQ: .word 0x361EF5F4,0x634BA0A0,0xB3729630,0xE627C364,0x185DE2BC,0x4D08B7E8


    .align 8 @: 256 byte boundary

crc8_table:
 .byte 0x00,0xD5,0x7F,0xAA,0xFE,0x2B,0x81,0x54,0x29,0xFC,0x56,0x83,0xD7,0x02,0xA8,0x7D
 .byte 0x52,0x87,0x2D,0xF8,0xAC,0x79,0xD3,0x06,0x7B,0xAE,0x04,0xD1,0x85,0x50,0xFA,0x2F
 .byte 0xA4,0x71,0xDB,0x0E,0x5A,0x8F,0x25,0xF0,0x8D,0x58,0xF2,0x27,0x73,0xA6,0x0C,0xD9
 .byte 0xF6,0x23,0x89,0x5C,0x08,0xDD,0x77,0xA2,0xDF,0x0A,0xA0,0x75,0x21,0xF4,0x5E,0x8B
 .byte 0x9D,0x48,0xE2,0x37,0x63,0xB6,0x1C,0xC9,0xB4,0x61,0xCB,0x1E,0x4A,0x9F,0x35,0xE0
 .byte 0xCF,0x1A,0xB0,0x65,0x31,0xE4,0x4E,0x9B,0xE6,0x33,0x99,0x4C,0x18,0xCD,0x67,0xB2
 .byte 0x39,0xEC,0x46,0x93,0xC7,0x12,0xB8,0x6D,0x10,0xC5,0x6F,0xBA,0xEE,0x3B,0x91,0x44
 .byte 0x6B,0xBE,0x14,0xC1,0x95,0x40,0xEA,0x3F,0x42,0x97,0x3D,0xE8,0xBC,0x69,0xC3,0x16
 .byte 0xEF,0x3A,0x90,0x45,0x11,0xC4,0x6E,0xBB,0xC6,0x13,0xB9,0x6C,0x38,0xED,0x47,0x92
 .byte 0xBD,0x68,0xC2,0x17,0x43,0x96,0x3C,0xE9,0x94,0x41,0xEB,0x3E,0x6A,0xBF,0x15,0xC0
 .byte 0x4B,0x9E,0x34,0xE1,0xB5,0x60,0xCA,0x1F,0x62,0xB7,0x1D,0xC8,0x9C,0x49,0xE3,0x36
 .byte 0x19,0xCC,0x66,0xB3,0xE7,0x32,0x98,0x4D,0x30,0xE5,0x4F,0x9A,0xCE,0x1B,0xB1,0x64
 .byte 0x72,0xA7,0x0D,0xD8,0x8C,0x59,0xF3,0x26,0x5B,0x8E,0x24,0xF1,0xA5,0x70,0xDA,0x0F
 .byte 0x20,0xF5,0x5F,0x8A,0xDE,0x0B,0xA1,0x74,0x09,0xDC,0x76,0xA3,0xF7,0x22,0x88,0x5D
 .byte 0xD6,0x03,0xA9,0x7C,0x28,0xFD,0x57,0x82,0xFF,0x2A,0x80,0x55,0x01,0xD4,0x7E,0xAB
 .byte 0x84,0x51,0xFB,0x2E,0x7A,0xAF,0x05,0xD0,0xAD,0x78,0xD2,0x07,0x53,0x86,0x2C,0xF9


 .align 8 @: 256 byte boundary

bbframe_scramble_table:
    .word 0x3408F603,0x93A3B830,0x73B768C9,0xF5AA29B3,0x88043CFE,0xA15A301B,0x9AC0C4DF,0xC20B5F83
    .word 0x2B938C38,0x1B7EFB6A,0xDC195A04,0xB4FAC954,0x9141B81F,0x5E1F6585,0x9D88C543,0xA7AB4E33
    .word 0xE014D0F9,0x861D417A,0x7DAE154D,0x295E0CE5,0x3B9AF4C4,0x58CB9B5C,0xE998D3BB,0x30ED7752
    .word 0xC767A16E,0x68E39350,0x25BB714B,0xCF5EDD9A,0xC397A0C6,0x3A238B70,0x47BF9ECA,0x66099183
    .word 0xFBB35437,0x54F019A8,0x12C4F821,0x63516F98,0xB15348E7,0xD975A4E9,0xF78AD63C,0xAF84323E
    .word 0x4D58E21B,0xEAE5ACD1,0x0CC97D5C,0xF9B42BB6,0x7D9C15BA,0x21B60F49,0x9DBAC5B4,0xAF434D9F
    .word 0x4634E189,0x719597B9,0xD202277F,0x6826EC0E,0x2EFF72D5,0x580EE402,0xE2DCD025,0xA7BD4ECA
    .word 0xE62CD18D,0xF57D56EA,0x84283E0C,0x5C2A1AF3,0xBC0CCAFD,0x32F9882B,0xE977AC16,0x37A17630
    .word 0xA397B0C6,0xBA24CB71,0x46D99EDB,0x76F196D7,0xBAD23427,0x45619EEF,0x41919F47,0x13518767
    .word 0x715568E6,0xD80224FF,0xE026D00E,0x8EF542D6,0xDB8E243D,0xDED6DA26,0x9436C6F6,0x19B37BB7
    .word 0xFCFD55AA,0x3028080C,0xCC23A2F0,0xFFB3AAC8,0x04F001A8,0x52C01820,0x6204EF81,0xA9574C19
    .word 0x3824F4F1,0x6ED392D8,0x557B66EB,0x0558FE1B,0x4AE01CD0,0x8D85BD41,0xE54E2E1D,0xCCD55DA6
    .word 0xFC0BAAFC,0x33900838,0xFB43AB60,0x56301988,0x30C4F7A1,0xCB53A398,0x9173B8E8,0x56F76629
    .word 0x3BA8F433,0x502398F0,0x4FB8E2CB,0xC765A191,0x68CB935C,0x299B73BB,0x30DEF75A,0xCF9BA2C4
    .word 0xC8D3A358,0xAD73B2E8,0x66F4EE29,0xFB975439,0x5A201B70,0xC784DEC1,0x6D5F921A,0x6B8B6CC3
    .word 0x1F9B7A3B,0x88DD435A,0xAFAE32CD,0x4150E0E7,0x194584E1,0xFF45559E,0x0748019C,0x65A011B0
    .word 0xCB875CC1,0x9D63BA10,0xA1B74F49,0x9DA4C5B1,0xAADB4CDB,0x06D4FED9,0x741016F8,0x97463961
    .word 0x27737197,0xEEFED22A,0x58156406,0xE600D17F,0xF80D5402,0x62E8102C,0xAE274D71,0x56E4E6D1
    .word 0x3CD4F559,0x3C138AF8,0x377F896A,0xAC0FB202,0x72C4E821,0xE3562F99,0xB03548F6,0xC98DA3BD
    .word 0xB6EBB62C,0xBE15B579,0x1E0D857D,0x9AE5442E,0xCCCF5D5D,0xF8C3ABA0,0x6A301388,0x00C77FA1
    .word 0x0B6C0392,0x9B703B68,0xDECB5A23,0x9192C7B8,0x5363676F,0x79B8EB4B,0x7F661591,0x08FE0355
    .word 0xA0183004,0x84E8C153,0x562A1973,0x340CF6FD,0x92F3B828,0x6AF76C29,0x0BAB7C33,0x901C38FA
    .word 0x45BB614B,0x4F599D9B,0xC2F1A0D7,0x2ADB8C24,0x06DEFEDA,0x779816C4,0xA8E63351,0x24F0F157
    .word 0xD2C2D820,0x6226EF8E,0xA6FF4ED5,0xF804D401,0x615C101A,0x9BB744C9,0xD5A759B1,0x0AE2FCD0
    .word 0x8DA83D4C,0xE82A2CF3,0x2C0572FE,0x7146E81E,0xDF7E2595,0x8C16C206,0xF6322977,0xB0E437AE
    .word 0xC4D9A15B,0x5EFB9AD4,0x9958C41B,0xFAEB54D3,0x4E101D78,0xDF45A561,0x874AC19C,0x658211BF
    .word 0xC42F5E0D,0x5D439AE0,0xAE38CD8B,0x5368E793,0x7A24EB71,0x46D61ED9,0x743D96F5,0x9A223B8F
    .word 0xC7A35ECF,0x63B390C8,0xB4FB49AB,0x9155B819,0x580F64FD,0xE2C8D023,0xA1AD4FB2,0x996CC4ED
    .word 0xF37B576B,0xFD502A18,0x294C0CE2,0x3CF2F5A8,0x32EB882C,0xEE1FAD7A,0x5D816540,0xA410CE07
    .word 0xD748D963,0x25AEF1B2,0xC95ADCE4,0xBAC7B4DE,0x43659F91,0x38C18B5F,0x6A179386,0x0E2B7D73
    .word 0xD41C26FA,0x15BEF94A,0x0E197D84,0xDCF42556,0xB39EC83A,0xF991AB47,0x73581764,0xF2E628D1
    .word 0xECF42D56,0x739D683A,0xF9A22B4F,0x7BA414CE,0x52D618D9,0x643CEEF5,0xDA375B89,0xC1A2DFB0
    .word 0x1BA784CE,0xD2ED58D2,0x6F6AED6C,0x4A0F637D,0x8AC9BC23,0x81BE3FB5,0x1E120587,0x9F69456C
    .word 0x8A3F4375,0x82063F81,0x29720C17,0x36EAF62C,0xBE0BB57C,0x1B958439,0xDA055B7E,0xC94ADC1C
    .word 0xBD87B5BE,0x25658E11,0xC0C6DF5E,0x0B778396,0x9FAC3A32,0x817B40EB,0x15560619,0x08397CF4
    .word 0xAB743396,0x1F98FA3B,0x88E14350,0xA59E3145,0xC190DF47,0x134F8762,0x74CD69A2,0x98E23BAF
    .word 0xE5A3514F,0xCBB15CC8,0x94DBB9A4,0x1ED77AD9,0x942D46F2,0x1D6F7AED,0xA34D4F62,0xB4ECC9AD
    .word 0x9779B96B,0x2D7F7215,0x640EEE02,0xD2DF5825,0x6782EEC0,0xEC2F520D,0x7D416AE0,0x2E120D87
    .word 0x5F6AE56C,0x8A0CC37D,0x8AFA3C2B,0x89423C1F,0xBE22358F,0x17A186CF,0x239570C6,0xBA06CB7E
    .word 0x49719C17,0xB6D1B627,0xB55DB6E5,0x8BADBCCD,0x916E38ED,0x53536767,0x7178E8EB,0xD5662611
    .word 0x00F6FF56,0x03B80034,0x37600990,0xA983B340,0x3434F609,0x9993BBB8,0xF3775769,0xFFA02A30
    .word 0x038C00C2,0x3EF00A28,0x1AC38420,0xC23D5F8A,0x222B8F8C,0xA41ECEFA,0xD590D947,0x034EFF62
    .word 0x34D809A4,0x9EE3BAD0,0x9DB74549,0xADA74DB1,0x6AE4ECD1,0x0CD77D59,0xFC2C2AF2,0x3D7C0AEA
    .word 0x24338E08,0xD8FEDBAA,0xE016D006,0x86354176,0x718E17BD,0xD6DE2625,0x3796F6C6,0xAA3BB374
    .word 0x0354FF99,0x301008F8,0xC743A160,0x66339188,0xF0FB57AB,0xC1502018,0x194F84E2,0xFCCD55A2
    .word 0x38E80BAC,0x66239170,0xF7BB56CB,0xA7503198,0xE148D0E3,0x9DAD45B2,0xA96F4CED,0x3344F761
    .word 0xF753A998,0xA17030E8,0x96C8C623,0x31AB77B3,0xD81FA4FA,0xE582D140,0xC4255E0E,0x5ECB9ADC
    .word 0x9198C7BB,0x50EB6753,0x4618E17B,0x7CE59551,0x34C2095F,0x9A2BBB8C,0xC4175EF9,0x56239970
    .word 0x37B8F6CB,0xA763B190,0xE9B4D349,0x3D9D75BA,0x21A78F4E,0x9AEEC4D2,0xCF535D67,0xC173A0E8
    .word 0x16F38628,0x3AFD742A,0x48279C0E,0xAEE9B2D3,0x5E3CE575,0x9234C789,0x619B6FBB,0x90DB475B
    .word 0x4ED762D9,0xD429A6F3,0x1C3AFAF4,0xBB494B9C,0x55BD99B5,0x0E20FD8F,0xD78026C0,0x2C0EF202
    .word 0x72DAE824,0xE6CE2EDD,0xF0D557A6,0xCC0822FC,0xF3AFA832,0xF14028E0,0xDE0C2582,0x9AFEC42A
    .word 0xC8135C07,0xA773B168,0xEEF4D229,0x5B9D643A,0xD9A0DB4F,0xFB8ED4C2,0x5ED41A26,0x9414C6F9
    .word 0x161B797B,0x3CDD755A,0x3FA78ACE,0x02EF80D2,0x2F4C0D62,0x44F2E1A8,0x52ED982D,0x6F60ED6F
    .word 0x49876341,0xB569B613,0x823DBF75,0x222E0F8D,0xA55ACEE4,0xCAC0DCDF,0x820FBF82,0x2AC60C21
    .word 0x037AFF94,0x3D480A1C,0x2DA38DB0,0x6BBEECCA,0x161F7985,0x3D8D7542,0x26E78E2E,0xFCEED552
    .word 0x37540966,0xA013B0F8,0x8774C169,0x6F9A123B,0x48CF635D,0xA8C9B3A3,0x29BCF3B5,0x3E32F588
    .word 0x10EB87AC,0x461D617A,0x7DA1954F,0x2B920CC7,0x1B6AFB6C,0xDA095B7C,0xCBBADC34,0x9747B99E
    .word 0x27677191,0xE8EED352,0x27557166,0xE006D0FE,0x81754016,0x178E063D,0x2ED97224,0x56F6E6D6
    .word 0x3BBCF435,0x56339988,0x30F8F7AB,0xC163A010,0x11B38748,0x5CFD65AA,0xB020C80F,0xCF89A2C3
    .word 0xCFBBA234,0xC753A198,0x617390E8,0x96FB462B,0x39577419,0x782F94F2,0x6D4A12E3,0x6D8F6DBD
    .word 0x66CB6E23,0xF19B57BB,0xD0D02758,0x4D4EE2E2,0xECDDADA5,0x7FA96ACC,0x003200F7,0x08E803AC
    .word 0xA6203170,0xF788D6C3,0xAFAC3232,0x4178E0EB,0x15658611,0x00C57F5E,0x0B44039E,0x97503998
    .word 0x214B70E3,0x9D9EC5BA,0x00000047




 .align 8 @: 256 byte boundary

bch_s168_table:
    .word 0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0,0 @: 0x00
    .word 0x00000040,0x62DBEA98,0x69B262CD,0x23A39069,0x528FE7D7,0xD11905A5,0,0 @: 0x01
    .word 0x00000080,0xC5B7D530,0xD364C59A,0x474720D2,0xA51FCFAF,0xA2320B4A,0,0 @: 0x02
    .word 0x000000C0,0xA76C3FA8,0xBAD6A757,0x64E4B0BB,0xF7902878,0x732B0EEF,0,0 @: 0x03
    .word 0x00000041,0xE9B440F9,0xCF7BE9F9,0xAD2DD1CC,0x18B07888,0x957D1331,0,0 @: 0x04
    .word 0x00000001,0x8B6FAA61,0xA6C98B34,0x8E8E41A5,0x4A3F9F5F,0x44641694,0,0 @: 0x05
    .word 0x000000C1,0x2C0395C9,0x1C1F2C63,0xEA6AF11E,0xBDAFB727,0x374F187B,0,0 @: 0x06
    .word 0x00000081,0x4ED87F51,0x75AD4EAE,0xC9C96177,0xEF2050F0,0xE6561DDE,0,0 @: 0x07
    .word 0x00000083,0xD36881F3,0x9EF7D3F3,0x5A5BA398,0x3160F111,0x2AFA2662,0,0 @: 0x08
    .word 0x000000C3,0xB1B36B6B,0xF745B13E,0x79F833F1,0x63EF16C6,0xFBE323C7,0,0 @: 0x09
    .word 0x00000003,0x16DF54C3,0x4D931669,0x1D1C834A,0x947F3EBE,0x88C82D28,0,0 @: 0x0A
    .word 0x00000043,0x7404BE5B,0x242174A4,0x3EBF1323,0xC6F0D969,0x59D1288D,0,0 @: 0x0B
    .word 0x000000C2,0x3ADCC10A,0x518C3A0A,0xF7767254,0x29D08999,0xBF873553,0,0 @: 0x0C
    .word 0x00000082,0x58072B92,0x383E58C7,0xD4D5E23D,0x7B5F6E4E,0x6E9E30F6,0,0 @: 0x0D
    .word 0x00000042,0xFF6B143A,0x82E8FF90,0xB0315286,0x8CCF4636,0x1DB53E19,0,0 @: 0x0E
    .word 0x00000002,0x9DB0FEA2,0xEB5A9D5D,0x9392C2EF,0xDE40A1E1,0xCCAC3BBC,0,0 @: 0x0F
    .word 0x00000047,0xC40AE97F,0x545DC52B,0x9714D759,0x304E05F5,0x84ED4961,0,0 @: 0x10
    .word 0x00000007,0xA6D103E7,0x3DEFA7E6,0xB4B74730,0x62C1E222,0x55F44CC4,0,0 @: 0x11
    .word 0x000000C7,0x01BD3C4F,0x873900B1,0xD053F78B,0x9551CA5A,0x26DF422B,0,0 @: 0x12
    .word 0x00000087,0x6366D6D7,0xEE8B627C,0xF3F067E2,0xC7DE2D8D,0xF7C6478E,0,0 @: 0x13
    .word 0x00000006,0x2DBEA986,0x9B262CD2,0x3A390695,0x28FE7D7D,0x11905A50,0,0 @: 0x14
    .word 0x00000046,0x4F65431E,0xF2944E1F,0x199A96FC,0x7A719AAA,0xC0895FF5,0,0 @: 0x15
    .word 0x00000086,0xE8097CB6,0x4842E948,0x7D7E2647,0x8DE1B2D2,0xB3A2511A,0,0 @: 0x16
    .word 0x000000C6,0x8AD2962E,0x21F08B85,0x5EDDB62E,0xDF6E5505,0x62BB54BF,0,0 @: 0x17
    .word 0x000000C4,0x1762688C,0xCAAA16D8,0xCD4F74C1,0x012EF4E4,0xAE176F03,0,0 @: 0x18
    .word 0x00000084,0x75B98214,0xA3187415,0xEEECE4A8,0x53A11333,0x7F0E6AA6,0,0 @: 0x19
    .word 0x00000044,0xD2D5BDBC,0x19CED342,0x8A085413,0xA4313B4B,0x0C256449,0,0 @: 0x1A
    .word 0x00000004,0xB00E5724,0x707CB18F,0xA9ABC47A,0xF6BEDC9C,0xDD3C61EC,0,0 @: 0x1B
    .word 0x00000085,0xFED62875,0x05D1FF21,0x6062A50D,0x199E8C6C,0x3B6A7C32,0,0 @: 0x1C
    .word 0x000000C5,0x9C0DC2ED,0x6C639DEC,0x43C13564,0x4B116BBB,0xEA737997,0,0 @: 0x1D
    .word 0x00000005,0x3B61FD45,0xD6B53ABB,0x272585DF,0xBC8143C3,0x99587778,0,0 @: 0x1E
    .word 0x00000045,0x59BA17DD,0xBF075876,0x048615B6,0xEE0EA414,0x484172DD,0,0 @: 0x1F
    .word 0x0000008F,0x8815D2FE,0xA8BB8A57,0x2E29AEB2,0x609C0BEB,0x09DA92C2,0,0 @: 0x20
    .word 0x000000CF,0xEACE3866,0xC109E89A,0x0D8A3EDB,0x3213EC3C,0xD8C39767,0,0 @: 0x21
    .word 0x0000000F,0x4DA207CE,0x7BDF4FCD,0x696E8E60,0xC583C444,0xABE89988,0,0 @: 0x22
    .word 0x0000004F,0x2F79ED56,0x126D2D00,0x4ACD1E09,0x970C2393,0x7AF19C2D,0,0 @: 0x23
    .word 0x000000CE,0x61A19207,0x67C063AE,0x83047F7E,0x782C7363,0x9CA781F3,0,0 @: 0x24
    .word 0x0000008E,0x037A789F,0x0E720163,0xA0A7EF17,0x2AA394B4,0x4DBE8456,0,0 @: 0x25
    .word 0x0000004E,0xA4164737,0xB4A4A634,0xC4435FAC,0xDD33BCCC,0x3E958AB9,0,0 @: 0x26
    .word 0x0000000E,0xC6CDADAF,0xDD16C4F9,0xE7E0CFC5,0x8FBC5B1B,0xEF8C8F1C,0,0 @: 0x27
    .word 0x0000000C,0x5B7D530D,0x364C59A4,0x74720D2A,0x51FCFAFA,0x2320B4A0,0,0 @: 0x28
    .word 0x0000004C,0x39A6B995,0x5FFE3B69,0x57D19D43,0x03731D2D,0xF239B105,0,0 @: 0x29
    .word 0x0000008C,0x9ECA863D,0xE5289C3E,0x33352DF8,0xF4E33555,0x8112BFEA,0,0 @: 0x2A
    .word 0x000000CC,0xFC116CA5,0x8C9AFEF3,0x1096BD91,0xA66CD282,0x500BBA4F,0,0 @: 0x2B
    .word 0x0000004D,0xB2C913F4,0xF937B05D,0xD95FDCE6,0x494C8272,0xB65DA791,0,0 @: 0x2C
    .word 0x0000000D,0xD012F96C,0x9085D290,0xFAFC4C8F,0x1BC365A5,0x6744A234,0,0 @: 0x2D
    .word 0x000000CD,0x777EC6C4,0x2A5375C7,0x9E18FC34,0xEC534DDD,0x146FACDB,0,0 @: 0x2E
    .word 0x0000008D,0x15A52C5C,0x43E1170A,0xBDBB6C5D,0xBEDCAA0A,0xC576A97E,0,0 @: 0x2F
    .word 0x000000C8,0x4C1F3B81,0xFCE64F7C,0xB93D79EB,0x50D20E1E,0x8D37DBA3,0,0 @: 0x30
    .word 0x00000088,0x2EC4D119,0x95542DB1,0x9A9EE982,0x025DE9C9,0x5C2EDE06,0,0 @: 0x31
    .word 0x00000048,0x89A8EEB1,0x2F828AE6,0xFE7A5939,0xF5CDC1B1,0x2F05D0E9,0,0 @: 0x32
    .word 0x00000008,0xEB730429,0x4630E82B,0xDDD9C950,0xA7422666,0xFE1CD54C,0,0 @: 0x33
    .word 0x00000089,0xA5AB7B78,0x339DA685,0x1410A827,0x48627696,0x184AC892,0,0 @: 0x34
    .word 0x000000C9,0xC77091E0,0x5A2FC448,0x37B3384E,0x1AED9141,0xC953CD37,0,0 @: 0x35
    .word 0x00000009,0x601CAE48,0xE0F9631F,0x535788F5,0xED7DB939,0xBA78C3D8,0,0 @: 0x36
    .word 0x00000049,0x02C744D0,0x894B01D2,0x70F4189C,0xBFF25EEE,0x6B61C67D,0,0 @: 0x37
    .word 0x0000004B,0x9F77BA72,0x62119C8F,0xE366DA73,0x61B2FF0F,0xA7CDFDC1,0,0 @: 0x38
    .word 0x0000000B,0xFDAC50EA,0x0BA3FE42,0xC0C54A1A,0x333D18D8,0x76D4F864,0,0 @: 0x39
    .word 0x000000CB,0x5AC06F42,0xB1755915,0xA421FAA1,0xC4AD30A0,0x05FFF68B,0,0 @: 0x3A
    .word 0x0000008B,0x381B85DA,0xD8C73BD8,0x87826AC8,0x9622D777,0xD4E6F32E,0,0 @: 0x3B
    .word 0x0000000A,0x76C3FA8B,0xAD6A7576,0x4E4B0BBF,0x79028787,0x32B0EEF0,0,0 @: 0x3C
    .word 0x0000004A,0x14181013,0xC4D817BB,0x6DE89BD6,0x2B8D6050,0xE3A9EB55,0,0 @: 0x3D
    .word 0x0000008A,0xB3742FBB,0x7E0EB0EC,0x090C2B6D,0xDC1D4828,0x9082E5BA,0,0 @: 0x3E
    .word 0x000000CA,0xD1AFC523,0x17BCD221,0x2AAFBB04,0x8E92AFFF,0x419BE01F,0,0 @: 0x3F
    .word 0x0000005F,0x72F04F65,0x38C57663,0x7FF0CD0D,0x93B7F001,0xC2AC2021,0,0 @: 0x40
    .word 0x0000001F,0x102BA5FD,0x517714AE,0x5C535D64,0xC13817D6,0x13B52584,0,0 @: 0x41
    .word 0x000000DF,0xB7479A55,0xEBA1B3F9,0x38B7EDDF,0x36A83FAE,0x609E2B6B,0,0 @: 0x42
    .word 0x0000009F,0xD59C70CD,0x8213D134,0x1B147DB6,0x6427D879,0xB1872ECE,0,0 @: 0x43
    .word 0x0000001E,0x9B440F9C,0xF7BE9F9A,0xD2DD1CC1,0x8B078889,0x57D13310,0,0 @: 0x44
    .word 0x0000005E,0xF99FE504,0x9E0CFD57,0xF17E8CA8,0xD9886F5E,0x86C836B5,0,0 @: 0x45
    .word 0x0000009E,0x5EF3DAAC,0x24DA5A00,0x959A3C13,0x2E184726,0xF5E3385A,0,0 @: 0x46
    .word 0x000000DE,0x3C283034,0x4D6838CD,0xB639AC7A,0x7C97A0F1,0x24FA3DFF,0,0 @: 0x47
    .word 0x000000DC,0xA198CE96,0xA632A590,0x25AB6E95,0xA2D70110,0xE8560643,0,0 @: 0x48
    .word 0x0000009C,0xC343240E,0xCF80C75D,0x0608FEFC,0xF058E6C7,0x394F03E6,0,0 @: 0x49
    .word 0x0000005C,0x642F1BA6,0x7556600A,0x62EC4E47,0x07C8CEBF,0x4A640D09,0,0 @: 0x4A
    .word 0x0000001C,0x06F4F13E,0x1CE402C7,0x414FDE2E,0x55472968,0x9B7D08AC,0,0 @: 0x4B
    .word 0x0000009D,0x482C8E6F,0x69494C69,0x8886BF59,0xBA677998,0x7D2B1572,0,0 @: 0x4C
    .word 0x000000DD,0x2AF764F7,0x00FB2EA4,0xAB252F30,0xE8E89E4F,0xAC3210D7,0,0 @: 0x4D
    .word 0x0000001D,0x8D9B5B5F,0xBA2D89F3,0xCFC19F8B,0x1F78B637,0xDF191E38,0,0 @: 0x4E
    .word 0x0000005D,0xEF40B1C7,0xD39FEB3E,0xEC620FE2,0x4DF751E0,0x0E001B9D,0,0 @: 0x4F
    .word 0x00000018,0xB6FAA61A,0x6C98B348,0xE8E41A54,0xA3F9F5F4,0x46416940,0,0 @: 0x50
    .word 0x00000058,0xD4214C82,0x052AD185,0xCB478A3D,0xF1761223,0x97586CE5,0,0 @: 0x51
    .word 0x00000098,0x734D732A,0xBFFC76D2,0xAFA33A86,0x06E63A5B,0xE473620A,0,0 @: 0x52
    .word 0x000000D8,0x119699B2,0xD64E141F,0x8C00AAEF,0x5469DD8C,0x356A67AF,0,0 @: 0x53
    .word 0x00000059,0x5F4EE6E3,0xA3E35AB1,0x45C9CB98,0xBB498D7C,0xD33C7A71,0,0 @: 0x54
    .word 0x00000019,0x3D950C7B,0xCA51387C,0x666A5BF1,0xE9C66AAB,0x02257FD4,0,0 @: 0x55
    .word 0x000000D9,0x9AF933D3,0x70879F2B,0x028EEB4A,0x1E5642D3,0x710E713B,0,0 @: 0x56
    .word 0x00000099,0xF822D94B,0x1935FDE6,0x212D7B23,0x4CD9A504,0xA017749E,0,0 @: 0x57
    .word 0x0000009B,0x659227E9,0xF26F60BB,0xB2BFB9CC,0x929904E5,0x6CBB4F22,0,0 @: 0x58
    .word 0x000000DB,0x0749CD71,0x9BDD0276,0x911C29A5,0xC016E332,0xBDA24A87,0,0 @: 0x59
    .word 0x0000001B,0xA025F2D9,0x210BA521,0xF5F8991E,0x3786CB4A,0xCE894468,0,0 @: 0x5A
    .word 0x0000005B,0xC2FE1841,0x48B9C7EC,0xD65B0977,0x65092C9D,0x1F9041CD,0,0 @: 0x5B
    .word 0x000000DA,0x8C266710,0x3D148942,0x1F926800,0x8A297C6D,0xF9C65C13,0,0 @: 0x5C
    .word 0x0000009A,0xEEFD8D88,0x54A6EB8F,0x3C31F869,0xD8A69BBA,0x28DF59B6,0,0 @: 0x5D
    .word 0x0000005A,0x4991B220,0xEE704CD8,0x58D548D2,0x2F36B3C2,0x5BF45759,0,0 @: 0x5E
    .word 0x0000001A,0x2B4A58B8,0x87C22E15,0x7B76D8BB,0x7DB95415,0x8AED52FC,0,0 @: 0x5F
    .word 0x000000D0,0xFAE59D9B,0x907EFC34,0x51D963BF,0xF32BFBEA,0xCB76B2E3,0,0 @: 0x60
    .word 0x00000090,0x983E7703,0xF9CC9EF9,0x727AF3D6,0xA1A41C3D,0x1A6FB746,0,0 @: 0x61
    .word 0x00000050,0x3F5248AB,0x431A39AE,0x169E436D,0x56343445,0x6944B9A9,0,0 @: 0x62
    .word 0x00000010,0x5D89A233,0x2AA85B63,0x353DD304,0x04BBD392,0xB85DBC0C,0,0 @: 0x63
    .word 0x00000091,0x1351DD62,0x5F0515CD,0xFCF4B273,0xEB9B8362,0x5E0BA1D2,0,0 @: 0x64
    .word 0x000000D1,0x718A37FA,0x36B77700,0xDF57221A,0xB91464B5,0x8F12A477,0,0 @: 0x65
    .word 0x00000011,0xD6E60852,0x8C61D057,0xBBB392A1,0x4E844CCD,0xFC39AA98,0,0 @: 0x66
    .word 0x00000051,0xB43DE2CA,0xE5D3B29A,0x981002C8,0x1C0BAB1A,0x2D20AF3D,0,0 @: 0x67
    .word 0x00000053,0x298D1C68,0x0E892FC7,0x0B82C027,0xC24B0AFB,0xE18C9481,0,0 @: 0x68
    .word 0x00000013,0x4B56F6F0,0x673B4D0A,0x2821504E,0x90C4ED2C,0x30959124,0,0 @: 0x69
    .word 0x000000D3,0xEC3AC958,0xDDEDEA5D,0x4CC5E0F5,0x6754C554,0x43BE9FCB,0,0 @: 0x6A
    .word 0x00000093,0x8EE123C0,0xB45F8890,0x6F66709C,0x35DB2283,0x92A79A6E,0,0 @: 0x6B
    .word 0x00000012,0xC0395C91,0xC1F2C63E,0xA6AF11EB,0xDAFB7273,0x74F187B0,0,0 @: 0x6C
    .word 0x00000052,0xA2E2B609,0xA840A4F3,0x850C8182,0x887495A4,0xA5E88215,0,0 @: 0x6D
    .word 0x00000092,0x058E89A1,0x129603A4,0xE1E83139,0x7FE4BDDC,0xD6C38CFA,0,0 @: 0x6E
    .word 0x000000D2,0x67556339,0x7B246169,0xC24BA150,0x2D6B5A0B,0x07DA895F,0,0 @: 0x6F
    .word 0x00000097,0x3EEF74E4,0xC423391F,0xC6CDB4E6,0xC365FE1F,0x4F9BFB82,0,0 @: 0x70
    .word 0x000000D7,0x5C349E7C,0xAD915BD2,0xE56E248F,0x91EA19C8,0x9E82FE27,0,0 @: 0x71
    .word 0x00000017,0xFB58A1D4,0x1747FC85,0x818A9434,0x667A31B0,0xEDA9F0C8,0,0 @: 0x72
    .word 0x00000057,0x99834B4C,0x7EF59E48,0xA229045D,0x34F5D667,0x3CB0F56D,0,0 @: 0x73
    .word 0x000000D6,0xD75B341D,0x0B58D0E6,0x6BE0652A,0xDBD58697,0xDAE6E8B3,0,0 @: 0x74
    .word 0x00000096,0xB580DE85,0x62EAB22B,0x4843F543,0x895A6140,0x0BFFED16,0,0 @: 0x75
    .word 0x00000056,0x12ECE12D,0xD83C157C,0x2CA745F8,0x7ECA4938,0x78D4E3F9,0,0 @: 0x76
    .word 0x00000016,0x70370BB5,0xB18E77B1,0x0F04D591,0x2C45AEEF,0xA9CDE65C,0,0 @: 0x77
    .word 0x00000014,0xED87F517,0x5AD4EAEC,0x9C96177E,0xF2050F0E,0x6561DDE0,0,0 @: 0x78
    .word 0x00000054,0x8F5C1F8F,0x33668821,0xBF358717,0xA08AE8D9,0xB478D845,0,0 @: 0x79
    .word 0x00000094,0x28302027,0x89B02F76,0xDBD137AC,0x571AC0A1,0xC753D6AA,0,0 @: 0x7A
    .word 0x000000D4,0x4AEBCABF,0xE0024DBB,0xF872A7C5,0x05952776,0x164AD30F,0,0 @: 0x7B
    .word 0x00000055,0x0433B5EE,0x95AF0315,0x31BBC6B2,0xEAB57786,0xF01CCED1,0,0 @: 0x7C
    .word 0x00000015,0x66E85F76,0xFC1D61D8,0x121856DB,0xB83A9051,0x2105CB74,0,0 @: 0x7D
    .word 0x000000D5,0xC18460DE,0x46CBC68F,0x76FCE660,0x4FAAB829,0x522EC59B,0,0 @: 0x7E
    .word 0x00000095,0xA35F8A46,0x2F79A442,0x555F7609,0x1D255FFE,0x8337C03E,0,0 @: 0x7F
    .word 0x000000BE,0xE5E09ECA,0x718AECC6,0xFFE19A1B,0x276FE003,0x85584042,0,0 @: 0x80
    .word 0x000000FE,0x873B7452,0x18388E0B,0xDC420A72,0x75E007D4,0x544145E7,0,0 @: 0x81
    .word 0x0000003E,0x20574BFA,0xA2EE295C,0xB8A6BAC9,0x82702FAC,0x276A4B08,0,0 @: 0x82
    .word 0x0000007E,0x428CA162,0xCB5C4B91,0x9B052AA0,0xD0FFC87B,0xF6734EAD,0,0 @: 0x83
    .word 0x000000FF,0x0C54DE33,0xBEF1053F,0x52CC4BD7,0x3FDF988B,0x10255373,0,0 @: 0x84
    .word 0x000000BF,0x6E8F34AB,0xD74367F2,0x716FDBBE,0x6D507F5C,0xC13C56D6,0,0 @: 0x85
    .word 0x0000007F,0xC9E30B03,0x6D95C0A5,0x158B6B05,0x9AC05724,0xB2175839,0,0 @: 0x86
    .word 0x0000003F,0xAB38E19B,0x0427A268,0x3628FB6C,0xC84FB0F3,0x630E5D9C,0,0 @: 0x87
    .word 0x0000003D,0x36881F39,0xEF7D3F35,0xA5BA3983,0x160F1112,0xAFA26620,0,0 @: 0x88
    .word 0x0000007D,0x5453F5A1,0x86CF5DF8,0x8619A9EA,0x4480F6C5,0x7EBB6385,0,0 @: 0x89
    .word 0x000000BD,0xF33FCA09,0x3C19FAAF,0xE2FD1951,0xB310DEBD,0x0D906D6A,0,0 @: 0x8A
    .word 0x000000FD,0x91E42091,0x55AB9862,0xC15E8938,0xE19F396A,0xDC8968CF,0,0 @: 0x8B
    .word 0x0000007C,0xDF3C5FC0,0x2006D6CC,0x0897E84F,0x0EBF699A,0x3ADF7511,0,0 @: 0x8C
    .word 0x0000003C,0xBDE7B558,0x49B4B401,0x2B347826,0x5C308E4D,0xEBC670B4,0,0 @: 0x8D
    .word 0x000000FC,0x1A8B8AF0,0xF3621356,0x4FD0C89D,0xABA0A635,0x98ED7E5B,0,0 @: 0x8E
    .word 0x000000BC,0x78506068,0x9AD0719B,0x6C7358F4,0xF92F41E2,0x49F47BFE,0,0 @: 0x8F
    .word 0x000000F9,0x21EA77B5,0x25D729ED,0x68F54D42,0x1721E5F6,0x01B50923,0,0 @: 0x90
    .word 0x000000B9,0x43319D2D,0x4C654B20,0x4B56DD2B,0x45AE0221,0xD0AC0C86,0,0 @: 0x91
    .word 0x00000079,0xE45DA285,0xF6B3EC77,0x2FB26D90,0xB23E2A59,0xA3870269,0,0 @: 0x92
    .word 0x00000039,0x8686481D,0x9F018EBA,0x0C11FDF9,0xE0B1CD8E,0x729E07CC,0,0 @: 0x93
    .word 0x000000B8,0xC85E374C,0xEAACC014,0xC5D89C8E,0x0F919D7E,0x94C81A12,0,0 @: 0x94
    .word 0x000000F8,0xAA85DDD4,0x831EA2D9,0xE67B0CE7,0x5D1E7AA9,0x45D11FB7,0,0 @: 0x95
    .word 0x00000038,0x0DE9E27C,0x39C8058E,0x829FBC5C,0xAA8E52D1,0x36FA1158,0,0 @: 0x96
    .word 0x00000078,0x6F3208E4,0x507A6743,0xA13C2C35,0xF801B506,0xE7E314FD,0,0 @: 0x97
    .word 0x0000007A,0xF282F646,0xBB20FA1E,0x32AEEEDA,0x264114E7,0x2B4F2F41,0,0 @: 0x98
    .word 0x0000003A,0x90591CDE,0xD29298D3,0x110D7EB3,0x74CEF330,0xFA562AE4,0,0 @: 0x99
    .word 0x000000FA,0x37352376,0x68443F84,0x75E9CE08,0x835EDB48,0x897D240B,0,0 @: 0x9A
    .word 0x000000BA,0x55EEC9EE,0x01F65D49,0x564A5E61,0xD1D13C9F,0x586421AE,0,0 @: 0x9B
    .word 0x0000003B,0x1B36B6BF,0x745B13E7,0x9F833F16,0x3EF16C6F,0xBE323C70,0,0 @: 0x9C
    .word 0x0000007B,0x79ED5C27,0x1DE9712A,0xBC20AF7F,0x6C7E8BB8,0x6F2B39D5,0,0 @: 0x9D
    .word 0x000000BB,0xDE81638F,0xA73FD67D,0xD8C41FC4,0x9BEEA3C0,0x1C00373A,0,0 @: 0x9E
    .word 0x000000FB,0xBC5A8917,0xCE8DB4B0,0xFB678FAD,0xC9614417,0xCD19329F,0,0 @: 0x9F
    .word 0x00000031,0x6DF54C34,0xD9316691,0xD1C834A9,0x47F3EBE8,0x8C82D280,0,0 @: 0xA0
    .word 0x00000071,0x0F2EA6AC,0xB083045C,0xF26BA4C0,0x157C0C3F,0x5D9BD725,0,0 @: 0xA1
    .word 0x000000B1,0xA8429904,0x0A55A30B,0x968F147B,0xE2EC2447,0x2EB0D9CA,0,0 @: 0xA2
    .word 0x000000F1,0xCA99739C,0x63E7C1C6,0xB52C8412,0xB063C390,0xFFA9DC6F,0,0 @: 0xA3
    .word 0x00000070,0x84410CCD,0x164A8F68,0x7CE5E565,0x5F439360,0x19FFC1B1,0,0 @: 0xA4
    .word 0x00000030,0xE69AE655,0x7FF8EDA5,0x5F46750C,0x0DCC74B7,0xC8E6C414,0,0 @: 0xA5
    .word 0x000000F0,0x41F6D9FD,0xC52E4AF2,0x3BA2C5B7,0xFA5C5CCF,0xBBCDCAFB,0,0 @: 0xA6
    .word 0x000000B0,0x232D3365,0xAC9C283F,0x180155DE,0xA8D3BB18,0x6AD4CF5E,0,0 @: 0xA7
    .word 0x000000B2,0xBE9DCDC7,0x47C6B562,0x8B939731,0x76931AF9,0xA678F4E2,0,0 @: 0xA8
    .word 0x000000F2,0xDC46275F,0x2E74D7AF,0xA8300758,0x241CFD2E,0x7761F147,0,0 @: 0xA9
    .word 0x00000032,0x7B2A18F7,0x94A270F8,0xCCD4B7E3,0xD38CD556,0x044AFFA8,0,0 @: 0xAA
    .word 0x00000072,0x19F1F26F,0xFD101235,0xEF77278A,0x81033281,0xD553FA0D,0,0 @: 0xAB
    .word 0x000000F3,0x57298D3E,0x88BD5C9B,0x26BE46FD,0x6E236271,0x3305E7D3,0,0 @: 0xAC
    .word 0x000000B3,0x35F267A6,0xE10F3E56,0x051DD694,0x3CAC85A6,0xE21CE276,0,0 @: 0xAD
    .word 0x00000073,0x929E580E,0x5BD99901,0x61F9662F,0xCB3CADDE,0x9137EC99,0,0 @: 0xAE
    .word 0x00000033,0xF045B296,0x326BFBCC,0x425AF646,0x99B34A09,0x402EE93C,0,0 @: 0xAF
    .word 0x00000076,0xA9FFA54B,0x8D6CA3BA,0x46DCE3F0,0x77BDEE1D,0x086F9BE1,0,0 @: 0xB0
    .word 0x00000036,0xCB244FD3,0xE4DEC177,0x657F7399,0x253209CA,0xD9769E44,0,0 @: 0xB1
    .word 0x000000F6,0x6C48707B,0x5E086620,0x019BC322,0xD2A221B2,0xAA5D90AB,0,0 @: 0xB2
    .word 0x000000B6,0x0E939AE3,0x37BA04ED,0x2238534B,0x802DC665,0x7B44950E,0,0 @: 0xB3
    .word 0x00000037,0x404BE5B2,0x42174A43,0xEBF1323C,0x6F0D9695,0x9D1288D0,0,0 @: 0xB4
    .word 0x00000077,0x22900F2A,0x2BA5288E,0xC852A255,0x3D827142,0x4C0B8D75,0,0 @: 0xB5
    .word 0x000000B7,0x85FC3082,0x91738FD9,0xACB612EE,0xCA12593A,0x3F20839A,0,0 @: 0xB6
    .word 0x000000F7,0xE727DA1A,0xF8C1ED14,0x8F158287,0x989DBEED,0xEE39863F,0,0 @: 0xB7
    .word 0x000000F5,0x7A9724B8,0x139B7049,0x1C874068,0x46DD1F0C,0x2295BD83,0,0 @: 0xB8
    .word 0x000000B5,0x184CCE20,0x7A291284,0x3F24D001,0x1452F8DB,0xF38CB826,0,0 @: 0xB9
    .word 0x00000075,0xBF20F188,0xC0FFB5D3,0x5BC060BA,0xE3C2D0A3,0x80A7B6C9,0,0 @: 0xBA
    .word 0x00000035,0xDDFB1B10,0xA94DD71E,0x7863F0D3,0xB14D3774,0x51BEB36C,0,0 @: 0xBB
    .word 0x000000B4,0x93236441,0xDCE099B0,0xB1AA91A4,0x5E6D6784,0xB7E8AEB2,0,0 @: 0xBC
    .word 0x000000F4,0xF1F88ED9,0xB552FB7D,0x920901CD,0x0CE28053,0x66F1AB17,0,0 @: 0xBD
    .word 0x00000034,0x5694B171,0x0F845C2A,0xF6EDB176,0xFB72A82B,0x15DAA5F8,0,0 @: 0xBE
    .word 0x00000074,0x344F5BE9,0x66363EE7,0xD54E211F,0xA9FD4FFC,0xC4C3A05D,0,0 @: 0xBF
    .word 0x000000E1,0x9710D1AF,0x494F9AA5,0x80115716,0xB4D81002,0x47F46063,0,0 @: 0xC0
    .word 0x000000A1,0xF5CB3B37,0x20FDF868,0xA3B2C77F,0xE657F7D5,0x96ED65C6,0,0 @: 0xC1
    .word 0x00000061,0x52A7049F,0x9A2B5F3F,0xC75677C4,0x11C7DFAD,0xE5C66B29,0,0 @: 0xC2
    .word 0x00000021,0x307CEE07,0xF3993DF2,0xE4F5E7AD,0x4348387A,0x34DF6E8C,0,0 @: 0xC3
    .word 0x000000A0,0x7EA49156,0x8634735C,0x2D3C86DA,0xAC68688A,0xD2897352,0,0 @: 0xC4
    .word 0x000000E0,0x1C7F7BCE,0xEF861191,0x0E9F16B3,0xFEE78F5D,0x039076F7,0,0 @: 0xC5
    .word 0x00000020,0xBB134466,0x5550B6C6,0x6A7BA608,0x0977A725,0x70BB7818,0,0 @: 0xC6
    .word 0x00000060,0xD9C8AEFE,0x3CE2D40B,0x49D83661,0x5BF840F2,0xA1A27DBD,0,0 @: 0xC7
    .word 0x00000062,0x4478505C,0xD7B84956,0xDA4AF48E,0x85B8E113,0x6D0E4601,0,0 @: 0xC8
    .word 0x00000022,0x26A3BAC4,0xBE0A2B9B,0xF9E964E7,0xD73706C4,0xBC1743A4,0,0 @: 0xC9
    .word 0x000000E2,0x81CF856C,0x04DC8CCC,0x9D0DD45C,0x20A72EBC,0xCF3C4D4B,0,0 @: 0xCA
    .word 0x000000A2,0xE3146FF4,0x6D6EEE01,0xBEAE4435,0x7228C96B,0x1E2548EE,0,0 @: 0xCB
    .word 0x00000023,0xADCC10A5,0x18C3A0AF,0x77672542,0x9D08999B,0xF8735530,0,0 @: 0xCC
    .word 0x00000063,0xCF17FA3D,0x7171C262,0x54C4B52B,0xCF877E4C,0x296A5095,0,0 @: 0xCD
    .word 0x000000A3,0x687BC595,0xCBA76535,0x30200590,0x38175634,0x5A415E7A,0,0 @: 0xCE
    .word 0x000000E3,0x0AA02F0D,0xA21507F8,0x138395F9,0x6A98B1E3,0x8B585BDF,0,0 @: 0xCF
    .word 0x000000A6,0x531A38D0,0x1D125F8E,0x1705804F,0x849615F7,0xC3192902,0,0 @: 0xD0
    .word 0x000000E6,0x31C1D248,0x74A03D43,0x34A61026,0xD619F220,0x12002CA7,0,0 @: 0xD1
    .word 0x00000026,0x96ADEDE0,0xCE769A14,0x5042A09D,0x2189DA58,0x612B2248,0,0 @: 0xD2
    .word 0x00000066,0xF4760778,0xA7C4F8D9,0x73E130F4,0x73063D8F,0xB03227ED,0,0 @: 0xD3
    .word 0x000000E7,0xBAAE7829,0xD269B677,0xBA285183,0x9C266D7F,0x56643A33,0,0 @: 0xD4
    .word 0x000000A7,0xD87592B1,0xBBDBD4BA,0x998BC1EA,0xCEA98AA8,0x877D3F96,0,0 @: 0xD5
    .word 0x00000067,0x7F19AD19,0x010D73ED,0xFD6F7151,0x3939A2D0,0xF4563179,0,0 @: 0xD6
    .word 0x00000027,0x1DC24781,0x68BF1120,0xDECCE138,0x6BB64507,0x254F34DC,0,0 @: 0xD7
    .word 0x00000025,0x8072B923,0x83E58C7D,0x4D5E23D7,0xB5F6E4E6,0xE9E30F60,0,0 @: 0xD8
    .word 0x00000065,0xE2A953BB,0xEA57EEB0,0x6EFDB3BE,0xE7790331,0x38FA0AC5,0,0 @: 0xD9
    .word 0x000000A5,0x45C56C13,0x508149E7,0x0A190305,0x10E92B49,0x4BD1042A,0,0 @: 0xDA
    .word 0x000000E5,0x271E868B,0x39332B2A,0x29BA936C,0x4266CC9E,0x9AC8018F,0,0 @: 0xDB
    .word 0x00000064,0x69C6F9DA,0x4C9E6584,0xE073F21B,0xAD469C6E,0x7C9E1C51,0,0 @: 0xDC
    .word 0x00000024,0x0B1D1342,0x252C0749,0xC3D06272,0xFFC97BB9,0xAD8719F4,0,0 @: 0xDD
    .word 0x000000E4,0xAC712CEA,0x9FFAA01E,0xA734D2C9,0x085953C1,0xDEAC171B,0,0 @: 0xDE
    .word 0x000000A4,0xCEAAC672,0xF648C2D3,0x849742A0,0x5AD6B416,0x0FB512BE,0,0 @: 0xDF
    .word 0x0000006E,0x1F050351,0xE1F410F2,0xAE38F9A4,0xD4441BE9,0x4E2EF2A1,0,0 @: 0xE0
    .word 0x0000002E,0x7DDEE9C9,0x8846723F,0x8D9B69CD,0x86CBFC3E,0x9F37F704,0,0 @: 0xE1
    .word 0x000000EE,0xDAB2D661,0x3290D568,0xE97FD976,0x715BD446,0xEC1CF9EB,0,0 @: 0xE2
    .word 0x000000AE,0xB8693CF9,0x5B22B7A5,0xCADC491F,0x23D43391,0x3D05FC4E,0,0 @: 0xE3
    .word 0x0000002F,0xF6B143A8,0x2E8FF90B,0x03152868,0xCCF46361,0xDB53E190,0,0 @: 0xE4
    .word 0x0000006F,0x946AA930,0x473D9BC6,0x20B6B801,0x9E7B84B6,0x0A4AE435,0,0 @: 0xE5
    .word 0x000000AF,0x33069698,0xFDEB3C91,0x445208BA,0x69EBACCE,0x7961EADA,0,0 @: 0xE6
    .word 0x000000EF,0x51DD7C00,0x94595E5C,0x67F198D3,0x3B644B19,0xA878EF7F,0,0 @: 0xE7
    .word 0x000000ED,0xCC6D82A2,0x7F03C301,0xF4635A3C,0xE524EAF8,0x64D4D4C3,0,0 @: 0xE8
    .word 0x000000AD,0xAEB6683A,0x16B1A1CC,0xD7C0CA55,0xB7AB0D2F,0xB5CDD166,0,0 @: 0xE9
    .word 0x0000006D,0x09DA5792,0xAC67069B,0xB3247AEE,0x403B2557,0xC6E6DF89,0,0 @: 0xEA
    .word 0x0000002D,0x6B01BD0A,0xC5D56456,0x9087EA87,0x12B4C280,0x17FFDA2C,0,0 @: 0xEB
    .word 0x000000AC,0x25D9C25B,0xB0782AF8,0x594E8BF0,0xFD949270,0xF1A9C7F2,0,0 @: 0xEC
    .word 0x000000EC,0x470228C3,0xD9CA4835,0x7AED1B99,0xAF1B75A7,0x20B0C257,0,0 @: 0xED
    .word 0x0000002C,0xE06E176B,0x631CEF62,0x1E09AB22,0x588B5DDF,0x539BCCB8,0,0 @: 0xEE
    .word 0x0000006C,0x82B5FDF3,0x0AAE8DAF,0x3DAA3B4B,0x0A04BA08,0x8282C91D,0,0 @: 0xEF
    .word 0x00000029,0xDB0FEA2E,0xB5A9D5D9,0x392C2EFD,0xE40A1E1C,0xCAC3BBC0,0,0 @: 0xF0
    .word 0x00000069,0xB9D400B6,0xDC1BB714,0x1A8FBE94,0xB685F9CB,0x1BDABE65,0,0 @: 0xF1
    .word 0x000000A9,0x1EB83F1E,0x66CD1043,0x7E6B0E2F,0x4115D1B3,0x68F1B08A,0,0 @: 0xF2
    .word 0x000000E9,0x7C63D586,0x0F7F728E,0x5DC89E46,0x139A3664,0xB9E8B52F,0,0 @: 0xF3
    .word 0x00000068,0x32BBAAD7,0x7AD23C20,0x9401FF31,0xFCBA6694,0x5FBEA8F1,0,0 @: 0xF4
    .word 0x00000028,0x5060404F,0x13605EED,0xB7A26F58,0xAE358143,0x8EA7AD54,0,0 @: 0xF5
    .word 0x000000E8,0xF70C7FE7,0xA9B6F9BA,0xD346DFE3,0x59A5A93B,0xFD8CA3BB,0,0 @: 0xF6
    .word 0x000000A8,0x95D7957F,0xC0049B77,0xF0E54F8A,0x0B2A4EEC,0x2C95A61E,0,0 @: 0xF7
    .word 0x000000AA,0x08676BDD,0x2B5E062A,0x63778D65,0xD56AEF0D,0xE0399DA2,0,0 @: 0xF8
    .word 0x000000EA,0x6ABC8145,0x42EC64E7,0x40D41D0C,0x87E508DA,0x31209807,0,0 @: 0xF9
    .word 0x0000002A,0xCDD0BEED,0xF83AC3B0,0x2430ADB7,0x707520A2,0x420B96E8,0,0 @: 0xFA
    .word 0x0000006A,0xAF0B5475,0x9188A17D,0x07933DDE,0x22FAC775,0x9312934D,0,0 @: 0xFB
    .word 0x000000EB,0xE1D32B24,0xE425EFD3,0xCE5A5CA9,0xCDDA9785,0x75448E93,0,0 @: 0xFC
    .word 0x000000AB,0x8308C1BC,0x8D978D1E,0xEDF9CCC0,0x9F557052,0xA45D8B36,0,0 @: 0xFD
    .word 0x0000006B,0x2464FE14,0x37412A49,0x891D7C7B,0x68C5582A,0xD77685D9,0,0 @: 0xFE
    .word 0x0000002B,0x46BF148C,0x5EF34884,0xAABEEC12,0x3A4ABFFD,0x066F807C,0,0 @: 0xFF


@: LDPC parameters

@: entry 0: original LDPC bit number (for information only), -1 for end of list
@: entry 1: offset to the group of 360 bits (45 bytes) in the BCH frame array
@: entry 2: offset of the row number in the intermediate LDPC array
@: entry 3: left shift value for first register
@: entry 4: adddress of the setup routine for the particlular first register


@: LDPC parameters - short frame, FEC 1/4, 5 words per entry

  .align 8 @: 256 byte boundary

ldpc_parameters_s14:
    .word 6295, 0 * 45, 31 * 64, 26, LDPC5first
    .word 9626, 0 * 45, 14 * 64, 29, LDPC2first
    .word 304, 0 * 45, 16 * 64, 0, LDPC11first
    .word 7695, 0 * 45, 27 * 64, 19, LDPC4first
    .word 4839, 0 * 45, 15 * 64, 2, LDPC7first
    .word 4936, 0 * 45, 4 * 64, 31, LDPC6first
    .word 1660, 0 * 45, 4 * 64, 26, LDPC9first
    .word 144, 0 * 45, 0 * 64, 4, LDPC11first
    .word 11203, 0 * 45, 7 * 64, 17, LDPC1first
    .word 5567, 0 * 45, 23 * 64, 14, LDPC6first
    .word 6347, 0 * 45, 11 * 64, 24, LDPC5first
    .word 12557, 0 * 45, 29 * 64, 12, LDPC0first
    .word 10691, 1 * 45, 35 * 64, 0, LDPC2first
    .word 4988, 1 * 45, 20 * 64, 30, LDPC6first
    .word 3859, 1 * 45, 7 * 64, 29, LDPC7first
    .word 3734, 1 * 45, 26 * 64, 1, LDPC8first
    .word 3071, 1 * 45, 11 * 64, 19, LDPC8first
    .word 3494, 1 * 45, 2 * 64, 7, LDPC8first
    .word 7687, 1 * 45, 19 * 64, 19, LDPC4first
    .word 10313, 1 * 45, 17 * 64, 10, LDPC2first
    .word 5964, 1 * 45, 24 * 64, 3, LDPC6first
    .word 8069, 1 * 45, 5 * 64, 8, LDPC4first
    .word 8296, 1 * 45, 16 * 64, 2, LDPC4first
    .word 11090, 1 * 45, 2 * 64, 20, LDPC1first
    .word 10774, 2 * 45, 10 * 64, 29, LDPC1first
    .word 3613, 2 * 45, 13 * 64, 4, LDPC8first
    .word 5208, 2 * 45, 24 * 64, 24, LDPC6first
    .word 11177, 2 * 45, 17 * 64, 18, LDPC1first
    .word 7676, 2 * 45, 8 * 64, 19, LDPC4first
    .word 3549, 2 * 45, 21 * 64, 6, LDPC8first
    .word 8746, 2 * 45, 34 * 64, 22, LDPC3first
    .word 6583, 2 * 45, 31 * 64, 18, LDPC5first
    .word 7239, 2 * 45, 3 * 64, 31, LDPC4first
    .word 12265, 2 * 45, 25 * 64, 20, LDPC0first
    .word 2674, 2 * 45, 10 * 64, 30, LDPC8first
    .word 4292, 2 * 45, 8 * 64, 17, LDPC7first
    .word 11869, 3 * 45, 25 * 64, 31, LDPC0first
    .word 3708, 3 * 45, 0 * 64, 1, LDPC8first
    .word 5981, 3 * 45, 5 * 64, 2, LDPC6first
    .word 8718, 3 * 45, 6 * 64, 22, LDPC3first
    .word 4908, 3 * 45, 12 * 64, 0, LDPC7first
    .word 10650, 3 * 45, 30 * 64, 1, LDPC2first
    .word 6805, 3 * 45, 1 * 64, 11, LDPC5first
    .word 3334, 3 * 45, 22 * 64, 12, LDPC8first
    .word 2627, 3 * 45, 35 * 64, 0, LDPC9first
    .word 10461, 3 * 45, 21 * 64, 6, LDPC2first
    .word 9285, 3 * 45, 33 * 64, 7, LDPC3first
    .word 11120, 3 * 45, 32 * 64, 20, LDPC1first
    .word 7844, 4 * 45, 32 * 64, 15, LDPC4first
    .word 3079, 4 * 45, 19 * 64, 19, LDPC8first
    .word 10773, 4 * 45, 9 * 64, 29, LDPC1first
    .word 3385, 5 * 45, 1 * 64, 10, LDPC8first
    .word 10854, 5 * 45, 18 * 64, 27, LDPC1first
    .word 5747, 5 * 45, 23 * 64, 9, LDPC6first
    .word 1360, 6 * 45, 28 * 64, 3, LDPC10first
    .word 12010, 6 * 45, 22 * 64, 27, LDPC0first
    .word 12202, 6 * 45, 34 * 64, 22, LDPC0first
    .word 6189, 7 * 45, 33 * 64, 29, LDPC5first
    .word 4241, 7 * 45, 29 * 64, 19, LDPC7first
    .word 2343, 7 * 45, 3 * 64, 7, LDPC9first
    .word 9840, 8 * 45, 12 * 64, 23, LDPC2first
    .word 12726, 8 * 45, 18 * 64, 7, LDPC0first
    .word 4977, 8 * 45, 9 * 64, 30, LDPC6first
 .word -1, 0, 0, 0, 0


@: LDPC parameters - short frame, FEC 3/4, 5 words per entry

 .align 8 @: 256 byte boundary

ldpc_parameters_s34:
    .word 3, 0 * 45, 3 * 64, 0, LDPC0first
    .word 3198, 0 * 45, 6 * 64, 30, LDPC2first
    .word 478, 0 * 45, 10 * 64, 1, LDPC10first
    .word 4207, 0 * 45, 7 * 64, 10, LDPC0first
    .word 1481, 0 * 45, 5 * 64, 13, LDPC7first
    .word 1009, 0 * 45, 1 * 64, 20, LDPC8first
    .word 2616, 0 * 45, 0 * 64, 14, LDPC4first
    .word 1924, 0 * 45, 4 * 64, 8, LDPC6first
    .word 3437, 0 * 45, 5 * 64, 10, LDPC2first
    .word 554, 0 * 45, 2 * 64, 26, LDPC9first
    .word 683, 0 * 45, 11 * 64, 16, LDPC9first
    .word 1801, 0 * 45, 1 * 64, 18, LDPC6first
    .word 4, 1 * 45, 4 * 64, 0, LDPC0first
    .word 2681, 1 * 45, 5 * 64, 9, LDPC4first
    .word 2135, 1 * 45, 11 * 64, 23, LDPC5first
    .word 5, 2 * 45, 5 * 64, 0, LDPC0first
    .word 3107, 2 * 45, 11 * 64, 6, LDPC3first
    .word 4027, 2 * 45, 7 * 64, 25, LDPC0first
    .word 6, 3 * 45, 6 * 64, 0, LDPC0first
    .word 2637, 3 * 45, 9 * 64, 13, LDPC4first
    .word 3373, 3 * 45, 1 * 64, 15, LDPC2first
    .word 7, 4 * 45, 7 * 64, 0, LDPC0first
    .word 3830, 4 * 45, 2 * 64, 9, LDPC1first
    .word 3449, 4 * 45, 5 * 64, 9, LDPC2first
    .word 8, 5 * 45, 8 * 64, 0, LDPC0first
    .word 4129, 5 * 45, 1 * 64, 16, LDPC0first
    .word 2060, 5 * 45, 8 * 64, 29, LDPC5first
    .word 9, 6 * 45, 9 * 64, 0, LDPC0first
    .word 4184, 6 * 45, 8 * 64, 12, LDPC0first
    .word 2742, 6 * 45, 6 * 64, 4, LDPC4first
    .word 10, 7 * 45, 10 * 64, 0, LDPC0first
    .word 3946, 7 * 45, 10 * 64, 0, LDPC1first
    .word 1070, 7 * 45, 2 * 64, 15, LDPC8first
    .word 11, 8 * 45, 11 * 64, 0, LDPC0first
    .word 2239, 8 * 45, 7 * 64, 14, LDPC5first
    .word 984, 8 * 45, 0 * 64, 22, LDPC8first
    .word 0, 9 * 45, 0 * 64, 0, LDPC0first
    .word 1458, 9 * 45, 6 * 64, 15, LDPC7first
    .word 3031, 9 * 45, 7 * 64, 12, LDPC3first
    .word 1, 10 * 45, 1 * 64, 0, LDPC0first
    .word 3003, 10 * 45, 3 * 64, 14, LDPC3first
    .word 1328, 10 * 45, 8 * 64, 26, LDPC7first
    .word 2, 11 * 45, 2 * 64, 0, LDPC0first
    .word 1137, 11 * 45, 9 * 64, 10, LDPC8first
    .word 1716, 11 * 45, 0 * 64, 25, LDPC6first
    .word 3, 12 * 45, 3 * 64, 0, LDPC0first
    .word 132, 12 * 45, 0 * 64, 29, LDPC10first
    .word 3725, 12 * 45, 5 * 64, 18, LDPC1first
    .word 4, 13 * 45, 4 * 64, 0, LDPC0first
    .word 1817, 13 * 45, 5 * 64, 17, LDPC6first
    .word 638, 13 * 45, 2 * 64, 19, LDPC9first
    .word 5, 14 * 45, 5 * 64, 0, LDPC0first
    .word 1774, 14 * 45, 10 * 64, 21, LDPC6first
    .word 3447, 14 * 45, 3 * 64, 9, LDPC2first
    .word 6, 15 * 45, 6 * 64, 0, LDPC0first
    .word 3632, 15 * 45, 8 * 64, 26, LDPC1first
    .word 1257, 15 * 45, 9 * 64, 0, LDPC8first
    .word 7, 16 * 45, 7 * 64, 0, LDPC0first
    .word 542, 16 * 45, 2 * 64, 27, LDPC9first
    .word 3694, 16 * 45, 10 * 64, 21, LDPC1first
    .word 8, 17 * 45, 8 * 64, 0, LDPC0first
    .word 1015, 17 * 45, 7 * 64, 20, LDPC8first
    .word 1945, 17 * 45, 1 * 64, 6, LDPC6first
    .word 9, 18 * 45, 9 * 64, 0, LDPC0first
    .word 1948, 18 * 45, 4 * 64, 6, LDPC6first
    .word 412, 18 * 45, 4 * 64, 6, LDPC10first
    .word 10, 19 * 45, 10 * 64, 0, LDPC0first
    .word 995, 19 * 45, 11 * 64, 22, LDPC8first
    .word 2238, 19 * 45, 6 * 64, 14, LDPC5first
    .word 11, 20 * 45, 11 * 64, 0, LDPC0first
    .word 4141, 20 * 45, 1 * 64, 15, LDPC0first
    .word 1907, 20 * 45, 11 * 64, 10, LDPC6first
    .word 0, 21 * 45, 0 * 64, 0, LDPC0first
    .word 2480, 21 * 45, 8 * 64, 26, LDPC4first
    .word 3079, 21 * 45, 7 * 64, 8, LDPC3first
    .word 1, 22 * 45, 1 * 64, 0, LDPC0first
    .word 3021, 22 * 45, 9 * 64, 13, LDPC3first
    .word 1088, 22 * 45, 8 * 64, 14, LDPC8first
    .word 2, 23 * 45, 2 * 64, 0, LDPC0first
    .word 713, 23 * 45, 5 * 64, 13, LDPC9first
    .word 1379, 23 * 45, 11 * 64, 22, LDPC7first
    .word 3, 24 * 45, 3 * 64, 0, LDPC0first
    .word 997, 24 * 45, 1 * 64, 21, LDPC8first
    .word 3903, 24 * 45, 3 * 64, 3, LDPC1first
    .word 4, 25 * 45, 4 * 64, 0, LDPC0first
    .word 2323, 25 * 45, 7 * 64, 7, LDPC5first
    .word 3361, 25 * 45, 1 * 64, 16, LDPC2first
    .word 5, 26 * 45, 5 * 64, 0, LDPC0first
    .word 1110, 26 * 45, 6 * 64, 12, LDPC8first
    .word 986, 26 * 45, 2 * 64, 22, LDPC8first
    .word 6, 27 * 45, 6 * 64, 0, LDPC0first
    .word 2532, 27 * 45, 0 * 64, 21, LDPC4first
    .word 142, 27 * 45, 10 * 64, 29, LDPC10first
    .word 7, 28 * 45, 7 * 64, 0, LDPC0first
    .word 1690, 28 * 45, 10 * 64, 28, LDPC6first
    .word 2405, 28 * 45, 5 * 64, 0, LDPC5first
    .word 8, 29 * 45, 8 * 64, 0, LDPC0first
    .word 1298, 29 * 45, 2 * 64, 28, LDPC7first
    .word 1881, 29 * 45, 9 * 64, 12, LDPC6first
    .word 9, 30 * 45, 9 * 64, 0, LDPC0first
    .word 615, 30 * 45, 3 * 64, 21, LDPC9first
    .word 174, 30 * 45, 6 * 64, 26, LDPC10first
    .word 10, 31 * 45, 10 * 64, 0, LDPC0first
    .word 1648, 31 * 45, 4 * 64, 31, LDPC6first
    .word 3112, 31 * 45, 4 * 64, 5, LDPC3first
    .word 11, 32 * 45, 11 * 64, 0, LDPC0first
    .word 1415, 32 * 45, 11 * 64, 19, LDPC7first
    .word 2808, 32 * 45, 0 * 64, 30, LDPC3first
 .word -1, 0, 0, 0, 0




 .data

 .align 8 @: 256 byte boundary

ldpc_xor_table:
    .byte 0x00,0x01,0x03,0x02,0x07,0x06,0x04,0x05,0x0F,0x0E,0x0C,0x0D,0x08,0x09,0x0B,0x0A @: 0x000
    .byte 0x1F,0x1E,0x1C,0x1D,0x18,0x19,0x1B,0x1A,0x10,0x11,0x13,0x12,0x17,0x16,0x14,0x15 @: 0x010
    .byte 0x3F,0x3E,0x3C,0x3D,0x38,0x39,0x3B,0x3A,0x30,0x31,0x33,0x32,0x37,0x36,0x34,0x35 @: 0x020
    .byte 0x20,0x21,0x23,0x22,0x27,0x26,0x24,0x25,0x2F,0x2E,0x2C,0x2D,0x28,0x29,0x2B,0x2A @: 0x030
    .byte 0x7F,0x7E,0x7C,0x7D,0x78,0x79,0x7B,0x7A,0x70,0x71,0x73,0x72,0x77,0x76,0x74,0x75 @: 0x040
    .byte 0x60,0x61,0x63,0x62,0x67,0x66,0x64,0x65,0x6F,0x6E,0x6C,0x6D,0x68,0x69,0x6B,0x6A @: 0x050
    .byte 0x40,0x41,0x43,0x42,0x47,0x46,0x44,0x45,0x4F,0x4E,0x4C,0x4D,0x48,0x49,0x4B,0x4A @: 0x060
    .byte 0x5F,0x5E,0x5C,0x5D,0x58,0x59,0x5B,0x5A,0x50,0x51,0x53,0x52,0x57,0x56,0x54,0x55 @: 0x070
    .byte 0xFF,0xFE,0xFC,0xFD,0xF8,0xF9,0xFB,0xFA,0xF0,0xF1,0xF3,0xF2,0xF7,0xF6,0xF4,0xF5 @: 0x080
    .byte 0xE0,0xE1,0xE3,0xE2,0xE7,0xE6,0xE4,0xE5,0xEF,0xEE,0xEC,0xED,0xE8,0xE9,0xEB,0xEA @: 0x090
    .byte 0xC0,0xC1,0xC3,0xC2,0xC7,0xC6,0xC4,0xC5,0xCF,0xCE,0xCC,0xCD,0xC8,0xC9,0xCB,0xCA @: 0x0A0
    .byte 0xDF,0xDE,0xDC,0xDD,0xD8,0xD9,0xDB,0xDA,0xD0,0xD1,0xD3,0xD2,0xD7,0xD6,0xD4,0xD5 @: 0x0B0
    .byte 0x80,0x81,0x83,0x82,0x87,0x86,0x84,0x85,0x8F,0x8E,0x8C,0x8D,0x88,0x89,0x8B,0x8A @: 0x0C0
    .byte 0x9F,0x9E,0x9C,0x9D,0x98,0x99,0x9B,0x9A,0x90,0x91,0x93,0x92,0x97,0x96,0x94,0x95 @: 0x0D0
    .byte 0xBF,0xBE,0xBC,0xBD,0xB8,0xB9,0xBB,0xBA,0xB0,0xB1,0xB3,0xB2,0xB7,0xB6,0xB4,0xB5 @: 0x0E0
    .byte 0xA0,0xA1,0xA3,0xA2,0xA7,0xA6,0xA4,0xA5,0xAF,0xAE,0xAC,0xAD,0xA8,0xA9,0xAB,0xAA @: 0x0F0
    .byte 0xFF,0xFE,0xFC,0xFD,0xF8,0xF9,0xFB,0xFA,0xF0,0xF1,0xF3,0xF2,0xF7,0xF6,0xF4,0xF5 @: 0x100
    .byte 0xE0,0xE1,0xE3,0xE2,0xE7,0xE6,0xE4,0xE5,0xEF,0xEE,0xEC,0xED,0xE8,0xE9,0xEB,0xEA @: 0x110
    .byte 0xC0,0xC1,0xC3,0xC2,0xC7,0xC6,0xC4,0xC5,0xCF,0xCE,0xCC,0xCD,0xC8,0xC9,0xCB,0xCA @: 0x120
    .byte 0xDF,0xDE,0xDC,0xDD,0xD8,0xD9,0xDB,0xDA,0xD0,0xD1,0xD3,0xD2,0xD7,0xD6,0xD4,0xD5 @: 0x130
    .byte 0x80,0x81,0x83,0x82,0x87,0x86,0x84,0x85,0x8F,0x8E,0x8C,0x8D,0x88,0x89,0x8B,0x8A @: 0x140
    .byte 0x9F,0x9E,0x9C,0x9D,0x98,0x99,0x9B,0x9A,0x90,0x91,0x93,0x92,0x97,0x96,0x94,0x95 @: 0x150
    .byte 0xBF,0xBE,0xBC,0xBD,0xB8,0xB9,0xBB,0xBA,0xB0,0xB1,0xB3,0xB2,0xB7,0xB6,0xB4,0xB5 @: 0x160
    .byte 0xA0,0xA1,0xA3,0xA2,0xA7,0xA6,0xA4,0xA5,0xAF,0xAE,0xAC,0xAD,0xA8,0xA9,0xAB,0xAA @: 0x170
    .byte 0x00,0x01,0x03,0x02,0x07,0x06,0x04,0x05,0x0F,0x0E,0x0C,0x0D,0x08,0x09,0x0B,0x0A @: 0x180
    .byte 0x1F,0x1E,0x1C,0x1D,0x18,0x19,0x1B,0x1A,0x10,0x11,0x13,0x12,0x17,0x16,0x14,0x15 @: 0x190
    .byte 0x3F,0x3E,0x3C,0x3D,0x38,0x39,0x3B,0x3A,0x30,0x31,0x33,0x32,0x37,0x36,0x34,0x35 @: 0x1A0
    .byte 0x20,0x21,0x23,0x22,0x27,0x26,0x24,0x25,0x2F,0x2E,0x2C,0x2D,0x28,0x29,0x2B,0x2A @: 0x1B0
    .byte 0x7F,0x7E,0x7C,0x7D,0x78,0x79,0x7B,0x7A,0x70,0x71,0x73,0x72,0x77,0x76,0x74,0x75 @: 0x1C0
    .byte 0x60,0x61,0x63,0x62,0x67,0x66,0x64,0x65,0x6F,0x6E,0x6C,0x6D,0x68,0x69,0x6B,0x6A @: 0x1D0
    .byte 0x40,0x41,0x43,0x42,0x47,0x46,0x44,0x45,0x4F,0x4E,0x4C,0x4D,0x48,0x49,0x4B,0x4A @: 0x1E0
    .byte 0x5F,0x5E,0x5C,0x5D,0x58,0x59,0x5B,0x5A,0x50,0x51,0x53,0x52,0x57,0x56,0x54,0x55 @: 0x1F0




 .align 8



symbols_scramble_table3:
    .byte 0x15,0x77,0x77,0x7F,0x76,0xA8,0x07,0xFB,0xF2,0x17,0xED,0x3C,0xDA,0xE2,0x11,0xC0
    .byte 0x29,0xA0,0xCB,0x9E,0xD8,0x86,0xA8,0x39,0xEA,0x91,0xCD,0x9F,0x33,0xA0,0xE8,0x31
    .byte 0xE7,0xDD,0x35,0x21,0x31,0xEF,0x89,0x2B,0x6C,0xFD,0xAD,0xBA,0x3A,0xE2,0x7C,0x16
    .byte 0x18,0x3A,0xE8,0x62,0x75,0xBD,0x6E,0xB2,0x3E,0x0F,0xF5,0x6B,0x59,0x94,0xC6,0x21
    .byte 0x18,0xFF,0x6C,0xB8,0x32,0x58,0xEB,0x22,0x8E,0xC4,0xFC,0xB4,0x61,0x59,0xE1,0xB5
    .byte 0x07,0xEC,0x09,0xD4,0x73,0x31,0x40,0x6D,0x23,0x48,0x31,0x4F,0x1D,0xC1,0x9B,0xC8
    .byte 0x91,0x70,0xD8,0x32,0xA0,0xA7,0xCE,0xBC,0xF6,0x04,0x56,0xC0,0xCD,0xAA,0xA8,0xDE
    .byte 0xDA,0x05,0x03,0x9F,0x80,0x6E,0xED,0xA6,0x54,0x8C,0xF3,0x54,0x0E,0x18,0x49,0xA9
    .byte 0x62,0xC5,0x87,0x65,0xA8,0x45,0x81,0x6F,0x8D,0x93,0x6E,0xFD,0xBF,0x2F,0xA1,0xB8
    .byte 0x72,0xA5,0x1C,0x80,0x15,0x28,0xD7,0xC1,0x6A,0x0F,0xA8,0xE1,0xDC,0xBE,0x71,0xED
    .byte 0x6C,0x25,0x48,0x04,0xEF,0xE6,0x7A,0x8A,0x51,0x98,0x30,0xC2,0x71,0x79,0xC0,0x77
    .byte 0xE4,0x1A,0x04,0x29,0x81,0xA0,0x40,0x34,0x8F,0x5D,0x0A,0x62,0x67,0x62,0x19,0x38
    .byte 0x3D,0x3A,0xB8,0xE7,0x42,0x7A,0xFA,0xF2,0xA8,0x8F,0x37,0x19,0xCA,0xA8,0xAB,0xC2
    .byte 0x83,0xA2,0x7E,0x75,0x32,0xDA,0xB0,0x71,0xA0,0xDD,0xC1,0x82,0x92,0x45,0x29,0x9D
    .byte 0x45,0xFA,0x72,0xF5,0x50,0x28,0x29,0xE9,0x86,0x80,0x6A,0x49,0xEC,0x56,0x86,0xE5
    .byte 0x8F,0x01,0xF2,0xCF,0xDC,0xEA,0x02,0x28,0x1F,0x4D,0x18,0x0B,0x57,0xCF,0xE9,0xB0
    .byte 0x2B,0x00,0xCB,0xD4,0x13,0x0B,0x15,0xB5,0xE1,0x3C,0xED,0x03,0x12,0x33,0x50,0x60
    .byte 0x12,0x0C,0x4F,0x8D,0x64,0x6E,0xF7,0x31,0x82,0x9D,0x33,0x9C,0x25,0x5F,0xB7,0xCE
    .byte 0x72,0x27,0x1E,0xD6,0x97,0xD7,0x89,0xF3,0xA2,0xF2,0x5F,0xAB,0xCA,0x28,0xAE,0x1B
    .byte 0x73,0x9E,0x0F,0x0A,0xC3,0x62,0x14,0x6A,0x2D,0xBF,0x44,0x34,0xF7,0x96,0x60,0x97
    .byte 0x79,0x39,0x6B,0x7B,0x9D,0x82,0x2F,0xC9,0x98,0xDD,0x0A,0xF9,0xE7,0xE1,0x9C,0x3A
    .byte 0x5C,0xE6,0x25,0x6A,0xD5,0xAD,0xB1,0xB2,0x29,0xDD,0xA2,0x33,0x50,0x14,0x57,0xAB
    .byte 0xD1,0x84,0x5B,0x11,0x8E,0x2C,0x65,0x02,0xEA,0x5B,0x87,0x60,0xC0,0x6B,0xAF,0x6E
    .byte 0xD4,0x1A,0x2D,0xC1,0x12,0x01,0xA4,0x1F,0x4D,0x8E,0xC2,0xDF,0xAA,0xE7,0xD6,0x65
    .byte 0x3B,0x45,0x46,0xDA,0xBA,0x03,0x7B,0x51,0x66,0x55,0x50,0x59,0x4B,0xD1,0xF3,0x99
    .byte 0xAA,0x31,0x7D,0xD3,0x34,0x12,0x09,0x38,0xC7,0x38,0x41,0x6F,0xD5,0x38,0x61,0xED
    .byte 0x67,0x03,0xBB,0xCE,0x0C,0xAD,0x8F,0x5D,0xD1,0xF7,0x7A,0x82,0x2E,0xD4,0xD0,0xD2
    .byte 0xD2,0x59,0x49,0xA8,0x3D,0x3C,0x7F,0x66,0x4C,0x8B,0x76,0x24,0xDF,0xF3,0x5A,0x0E
    .byte 0xC2,0xCD,0xB2,0xC9,0xAE,0xFE,0xB3,0x05,0x6A,0x99,0x8C,0x61,0x25,0x9F,0xFC,0xE9
    .byte 0x62,0x39,0xE1,0xA3,0xF0,0xB8,0xC4,0x1F,0x61,0xEF,0xFE,0x76,0x90,0xB5,0x93,0x5F
    .byte 0x1A,0x5F,0xFF,0x17,0xDF,0x5C,0xD3,0xBD,0x9C,0x0A,0xF4,0xE7,0x4F,0xD9,0xCA,0x99
    .byte 0x79,0xBE,0xA7,0x1B,0x8A,0xDB,0x30,0xC5,0xAB,0x73,0x4B,0xD6,0x3E,0xDC,0x58,0xAA
    .byte 0x1D,0x29,0xAA,0x2B,0x72,0xFB,0x8E,0x1E,0xD1,0xB3,0xD3,0x54,0xF3,0x68,0x0D,0x79
    .byte 0x07,0x87,0x8D,0xAD,0x4B,0x3D,0x8C,0x37,0xBE,0xC2,0xD8,0x73,0xA0,0x0C,0x93,0xD4
    .byte 0xE0,0x0B,0x1E,0xAF,0xDB,0xDD,0xB1,0x2B,0xE8,0x5C,0x3E,0x78,0x3E,0xFC,0x1A,0x0E
    .byte 0xD5,0x77,0x51,0xA6,0xCF,0xAA,0x80,0x2B,0x94,0x6D,0x5C,0xBA,0x5B,0x49,0x01,0x7D
    .byte 0x02,0xA5,0x2C,0x38,0x20,0xBC,0x0E,0x2C,0x0B,0x42,0xCC,0xC3,0x3A,0x83,0xFA,0x1A
    .byte 0x7B,0x32,0x22,0x90,0xCA,0xDD,0xA2,0x55,0x89,0x10,0xB9,0x30,0x4D,0xAE,0x57,0x27
    .byte 0xAD,0xE8,0xBA,0xB6,0x98,0xF4,0x6C,0xCC,0x81,0xCF,0x1F,0x01,0x6D,0x40,0x83,0x1B
    .byte 0x03,0xD4,0xDB,0x9E,0x4C,0x52,0x3A,0xE4,0x6C,0xC8,0x4A,0x2E,0xF1,0x87,0x04,0x38
    .byte 0xE5,0x11,0x11,0x26,0x69,0xEE,0xC9,0x86,0x95,0x60,0x8B,0xF7,0xF5,0x25,0xE8,0x1A
    .byte 0x91,0x94,0x97,0xED,0x8C,0xDE,0x81,0xA4,0xFC,0xBF,0xBD,0x5C,0xAC,0x46,0xA5,0x05
    .byte 0x03,0x5C,0xB0,0xAF,0x01,0x3D,0xEC,0x2C,0x66,0x77,0xE6,0x22,0x91,0x9C,0x8C,0x93
    .byte 0x2E,0x26,0x36,0xFE,0x1A,0x40,0x6D,0x7A,0x14,0xCE,0xE9,0xD2,0x19,0x2C,0x5A,0xE4
    .byte 0xEA,0xD7,0x21,0x5C,0x80,0x93,0xC5,0xF7,0x9A,0x33,0xBB,0x37,0x11,0xAF,0xD6,0x37
    .byte 0xCD,0x25,0x5A,0xA1,0xF5,0x45,0x5C,0xF9,0x2C,0x37,0xF6,0x96,0xAD,0x9F,0x9C,0xDD
    .byte 0x08,0xEA,0xB2,0xC8,0x74,0x54,0xD6,0xA5,0x29,0x80,0x44,0x5F,0x58,0x52,0xA3,0xCB
    .byte 0xCC,0xC5,0xCD,0x7D,0x58,0x64,0x71,0xDE,0x23,0x07,0x3E,0xD5,0xB0,0x7E,0x4B,0xA4
    .byte 0xF0,0xAB,0xF0,0x4C,0x48,0x6A,0x11,0x7F,0x17,0x09,0x80,0x05,0x74,0x40,0xEA,0x11
    .byte 0xD4,0x99,0x3D,0xDB,0xCD,0x1C,0xB7,0xF6,0xAF,0xE5,0xEE,0xC5,0x21,0x5D,0xFF,0x86
    .byte 0xA9,0x3F,0x07,0x06,0xCA,0x21,0x04,0x36,0x32,0x10,0x9C,0x03,0xB9,0xB4,0xBA,0xCE
    .byte 0x72,0x8E,0x6A,0x0F,0x48,0xB1,0x10,0x08,0x29,0x7E,0xFE,0x48,0xAD,0x54,0x09,0xB0
    .byte 0x26,0xF3,0x6F,0xC1,0x3C,0x55,0x38,0xC6,0xA7,0xBC,0x64,0x5E,0x46,0x91,0xA0,0xB2
    .byte 0xC2,0x69,0x4E,0xA4,0xEA,0x6B,0x3D,0xDB,0xBF,0xDA,0x34,0x61,0xF2,0xE8,0xE7,0x92
    .byte 0x2F,0x8F,0xA0,0x61,0xB1,0xAF,0x14,0x60,0x89,0x0E,0x93,0x1F,0x56,0xBC,0x44,0xC4
    .byte 0x99,0xE7,0xD3,0x2F,0x31,0xDA,0x84,0x08,0x71,0x86,0x6D,0x8A,0xA9,0x43,0xF6,0x02
    .byte 0x91,0xCA,0xB9,0x19,0x47,0x1D,0x14,0x29,0x70,0xD7,0x82,0xBA,0x90,0x56,0xC7,0xEB
    .byte 0x03,0x0D,0x43,0x85,0x02,0x37,0x1C,0xFB,0xCD,0xEF,0x5D,0x5D,0xE6,0xEB,0xE7,0xD0
    .byte 0x9B,0x94,0x0C,0x3C,0x49,0xBC,0x49,0x56,0xE6,0x92,0xF0,0x10,0x0D,0x23,0x3A,0x26
    .byte 0x20,0x60,0xA8,0x72,0xA7,0xBE,0xB6,0x78,0x11,0x36,0x42,0xA7,0x39,0xB0,0xAD,0x63
    .byte 0x6D,0x98,0x1A,0x09,0xC1,0xC1,0xA4,0x39,0x1D,0x6F,0xA4,0x42,0xE8,0xF2,0x4D,0xDA
    .byte 0x2C,0x61,0x24,0x2B,0x01,0x57,0x02,0x97,0xE4,0x23,0x48,0x6A,0x6A,0xB5,0x78,0x06
    .byte 0x81,0xD1,0x30,0x39,0x31,0x23,0xDA,0x12,0x57,0x4C,0xFD,0x69,0xDC,0x23,0xF8,0xC5
    .byte 0xFC,0x0D,0x78,0x15,0x3E,0xFE,0xAD,0xA4,0x5D,0xFA,0xA1,0x8C,0x3D,0xAC,0x3B,0x96
    .byte 0xA0,0x8E,0xAD,0xEC,0xEF,0x0D,0x2E,0x8C,0xD3,0x1D,0xAC,0xA2,0x1C,0xF7,0xDA,0x29
    .byte 0x13,0x40,0x1B,0x0D,0xBB,0x9F,0x51,0x96,0x4E,0xD9,0xA3,0xF2,0x12,0x8C,0x96,0x21
    .byte 0x56,0x8A,0xA1,0x81,0x03,0x05,0xB6,0x98,0x1B,0x0C,0x84,0x1B,0x2E,0x33,0xEF,0x4A
    .byte 0xF6,0xC8,0x88,0xCE,0x97,0xC7,0x3D,0xA9,0xEB,0x46,0x74,0xB0,0x07,0xE6,0xC2,0x3A
    .byte 0xA7,0x9C,0x5F,0x7D,0x70,0xDB,0x44,0xF2,0x4E,0x6B,0x54,0x23,0x06,0x4B,0xE7,0x6F
    .byte 0x91,0x3D,0x0C,0x0D,0xE8,0xC3,0xB2,0x2E,0x82,0x17,0xB0,0x30,0x8A,0xD6,0x98,0x71
    .byte 0x01,0x1B,0xBF,0x5A,0x50,0x87,0x5F,0x03,0x93,0xF3,0x55,0x47,0x65,0x5A,0x97,0x7E
    .byte 0xA4,0x75,0xF1,0x6F,0x8D,0x6E,0x0F,0x48,0xBD,0x0C,0xC4,0x09,0xE4,0xCE,0x60,0x9A
    .byte 0x80,0xC8,0xB5,0x6D,0xF8,0xA5,0xE9,0x4B,0x86,0x95,0xF3,0xA2,0xD4,0xCC,0x3C,0xD3
    .byte 0x43,0xEB,0xA9,0xF3,0xDD,0xD8,0x79,0x96,0x90,0x43,0xE5,0xE5,0x4C,0x87,0xF9,0x19
    .byte 0x1F,0xA5,0x42,0x46,0x0F,0x22,0x1C,0x3E,0x99,0x0D,0x2F,0x70,0x12,0xCC,0x48,0xDC
    .byte 0x6B,0xAE,0xE2,0x5C,0x42,0xFE,0x96,0xA4,0x03,0x67,0xDE,0x96,0xD5,0x5A,0x3E,0xBF
    .byte 0xD0,0xEB,0xE7,0xCC,0x97,0x62,0x48,0x42,0x7B,0x8B,0xBE,0xD1,0x2C,0x2F,0x11,0x56
    .byte 0x1A,0x59,0x7F,0x7C,0x25,0xF8,0x2B,0x2E,0x85,0x85,0xB2,0x22,0x99,0xE9,0x66,0x90
    .byte 0x65,0x14,0x07,0x4E,0xDF,0x18,0x1D,0x90,0xD7,0x09,0x19,0x1E,0xEF,0xFF,0x48,0x96
    .byte 0x19,0x69,0x52,0x5B,0xC4,0x06,0xC4,0xC4,0xBB,0x1B,0x89,0x31,0xF2,0x23,0x84,0xBF
    .byte 0x41,0xFE,0x10,0x4B,0x9C,0xB4,0xED,0x6B,0xA3,0x6D,0x7B,0x3F,0x42,0xA4,0x16,0x57
    .byte 0xBB,0x36,0xA3,0xC8,0x37,0x17,0x91,0x32,0x3A,0x1C,0x54,0x4A,0xF4,0xDC,0x7C,0x11
    .byte 0x6F,0x37,0x41,0xB5,0x2A,0x9A,0x3C,0x5F,0xCD,0x34,0x52,0x33,0x25,0x37,0xF1,0x57
    .byte 0x2F,0x01,0x9D,0x8A,0x3D,0x9B,0x06,0x27,0xFF,0xC8,0x2A,0x68,0xEF,0xF6,0xAA,0x4B
    .byte 0x22,0xC1,0x95,0x4A,0xBA,0xCC,0x0D,0x45,0x8C,0x3C,0xC4,0x75,0x65,0x37,0x65,0x57
    .byte 0xC7,0x01,0x02,0x66,0x3A,0xFC,0xCE,0x20,0x96,0x18,0x13,0x00,0x7A,0x5E,0xE0,0xB8
    .byte 0xAC,0x28,0x75,0x86,0x71,0x13,0x89,0x36,0x76,0xA4,0x8C,0x4B,0x9C,0x4F,0x50,0x4F
    .byte 0x81,0x38,0xDB,0x45,0x30,0x65,0x66,0x8C,0xC2,0xD4,0xC4,0x84,0x9E,0x33,0x30,0xE6
    .byte 0xE9,0x46,0xEE,0x0A,0xD5,0xC0,0xAF,0xDA,0xD7,0x13,0xF9,0x4A,0x53,0xB5,0x3A,0x5D
    .byte 0x2A,0xBE,0x52,0x10,0x41,0x83,0x33,0x65,0x73,0x49,0x0D,0x63,0x6A,0xA4,0x48,0x00
    .byte 0x8F,0x6C,0x94,0xA5,0x08,0xCE,0x66,0xC7,0xEB,0xFF,0x89,0x3A,0x03,0x93,0xCC,0xF6
    .byte 0x4A,0x17,0x79,0x41,0x2E,0xA6,0x0C,0xDC,0xE5,0x35,0x6E,0x6E,0x0A,0xC8,0xA9,0xBC
    .byte 0x35,0xE5,0xB2,0x76,0xC6,0x01,0x0B,0xC0,0xF5,0x04,0xE7,0x0E,0x6C,0x52,0x38,0x47
    .byte 0xD8,0x06,0x56,0x7B,0x68,0x14,0x79,0x53,0xE2,0x86,0xE7,0xF2,0x79,0x00,0x9B,0xF7
    .byte 0x3D,0x66,0x15,0x71,0xAB,0x41,0x98,0xE8,0xAF,0xBA,0xA5,0xCD,0x3A,0x9B,0x5F,0x93
    .byte 0xC8,0xA9,0x2C,0x33,0x7D,0x5B,0x4E,0x95,0x19,0x18,0x57,0xBF,0x90,0xF3,0xA6,0x5F
    .byte 0x3C,0xB0,0x45,0x89,0x10,0xFD,0xDD,0x0A,0x72,0x83,0xEF,0x25,0x7C,0x8E,0xCE,0x0C
    .byte 0x9B,0xB0,0xFF,0x7E,0x34,0x4D,0x77,0xC5,0xF9,0x7B,0xE3,0x03,0xD9,0xF9,0x55,0xB1
    .byte 0x69,0x9B,0x6C,0x88,0x30,0x35,0x36,0xAF,0x1E,0xE5,0xF8,0xD1,0xBA,0x04,0xF7,0x57
    .byte 0xCE,0x4C,0x0F,0x37,0x37,0xFA,0x45,0xCB,0x35,0xCC,0xE5,0xE4,0xEF,0xF0,0x92,0x6B
    .byte 0x94,0x02,0xC9,0xDE,0x81,0xE5,0x29,0x30,0x69,0x49,0xE3,0xED,0x41,0x80,0x27,0xF4
    .byte 0x24,0xB2,0x92,0xE8,0xDF,0x56,0x9D,0x0D,0x18,0x72,0x5F,0xBB,0xC6,0xC4,0x8D,0x32
    .byte 0x3E,0x27,0x7A,0xCC,0x8D,0xFC,0xAC,0xC3,0x8A,0xD4,0x1E,0x24,0xF4,0x40,0x7D,0x9F
    .byte 0xAB,0x02,0x9E,0x90,0x76,0xD2,0x8F,0x2D,0x17,0x8A,0xF2,0xBB,0xBA,0x6B,0x6F,0x29
    .byte 0x1E,0x0C,0x9E,0x90,0xC0,0x92,0xEE,0x36,0x66,0xD6,0x13,0x9F,0xCE,0xB8,0x36,0xE8
    .byte 0x01,0xBB,0x1A,0xDC,0xAA,0x34,0x08,0xF2,0x1F,0x0E,0xE0,0x15,0x58,0xF7,0xBF,0xF1
    .byte 0x56,0x18,0x78,0x04,0x76,0xDF,0x3C,0xA6,0x4C,0x46,0xBD,0x0F,0xEF,0x93,0x77,0xD0
    .byte 0x3D,0xC4,0xDE,0xCB,0x63,0x07,0x6C,0xC6,0xD8,0x2E,0xAE,0x99,0x2F,0x4B,0xB0,0x8B
    .byte 0x0D,0x5A,0xDC,0x95,0x81,0x25,0x2E,0x89,0x37,0xA4,0xE2,0xBC,0x2A,0xBD,0x57,0xA7
    .byte 0xD8,0xA9,0xA9,0xD0,0xF2,0xA7,0xEC,0x4D,0x6D,0x40,0x38,0xB3,0x11,0x3A,0x44,0x52
    .byte 0x8E,0xE3,0xE2,0x28,0x42,0x2C,0x24,0x89,0x99,0x07,0x84,0x7C,0x6D,0x53,0x42,0xB4
    .byte 0xB1,0xAB,0x39,0x4A,0x15,0xB6,0x52,0x44,0x7B,0xE4,0x92,0x2A,0x75,0x0A,0x10,0x8F
    .byte 0xA9,0x99,0x8C,0xF1,0x93,0x14,0x4B,0xF5,0xBA,0x43,0x07,0x29,0x4C,0xD2,0xF4,0xD7
    .byte 0x3C,0x20,0x08,0xAE,0xD0,0xB2,0xF7,0x6E,0xC5,0xE4,0xE1,0xAD,0x61,0x6D,0x81,0x0B
    .byte 0xA3,0xD9,0x94,0xC2,0x2D,0x5E,0x36,0x54,0xAC,0x05,0x11,0x03,0x85,0xD9,0x70,0x8C
    .byte 0xBC,0x54,0x5B,0xB5,0x87,0xFD,0x92,0x64,0x63,0xA4,0x96,0x23,0x29,0xFD,0x98,0xBB
    .byte 0x3C,0xF8,0x9C,0xF4,0x00,0x7C,0x00,0xC5,0x5D,0x61,0x50,0xC2,0x24,0x8F,0x30,0xF2
    .byte 0xE2,0x98,0x8E,0x8F,0x7F,0xED,0x17,0xCA,0x47,0x60,0xD5,0xDF,0xEE,0x2E,0x3D,0xA7
    .byte 0x9B,0x28,0x8F,0xBD,0xB8,0xA0,0x7D,0x41,0x94,0x18,0xBA,0xDC,0x4B,0x17,0x07,0x47
    .byte 0x3E,0xE9,0x7E,0x26,0x2B,0xD5,0xAE,0x2C,0x74,0xD5,0x4C,0xA4,0x57,0x50,0xB8,0xA4
    .byte 0xD0,0xDD,0x3B,0xF8,0x5F,0x83,0xF7,0x53,0x46,0xB6,0x8D,0x24,0x56,0xDF,0x82,0xF1
    .byte 0xDA,0x65,0xE4,0x4E,0x90,0xB5,0xA1,0x58,0xD0,0xDC,0xD6,0x57,0x60,0xA7,0xE6,0xF8
    .byte 0xF7,0x64,0x4F,0x9A,0x57,0xB3,0x12,0x4B,0x40,0x71,0xCD,0x37,0x3F,0x05,0xBC,0xAB
    .byte 0xE9,0x28,0x2C,0x9F,0x2F,0xC6,0x9A,0x94,0x7F,0x60,0x7B,0x16,0x88,0xBA,0xAE,0xAE
    .byte 0x7E,0x16,0xD8,0x89,0x3E,0x06,0x3F,0xA6,0xF1,0x66,0x39,0x5D,0x2C,0x03,0x93,0x1A
    .byte 0x4B,0x3D,0x3E,0x54,0xEE,0x9A,0x9C,0xFF,0x57,0xA2,0x8F,0xB3,0x8E,0x0F,0xD9,0x43
    .byte 0x69,0x20,0xCC,0xCC,0xB2,0x0B,0xA5,0x7E,0xFE


 .align 8



symbols_scramble_table4:
    .byte 0x00,0x01,0x04,0x05,0x02,0x03,0x06,0x07,0x08,0x09,0x0C,0x0D,0x0A,0x0B,0x0E,0x0F
    .byte 0x04,0x00,0x05,0x01,0x06,0x02,0x07,0x03,0x0C,0x08,0x0D,0x09,0x0E,0x0A,0x0F,0x0B
    .byte 0x05,0x04,0x01,0x00,0x07,0x06,0x03,0x02,0x0D,0x0C,0x09,0x08,0x0F,0x0E,0x0B,0x0A
    .byte 0x01,0x05,0x00,0x04,0x03,0x07,0x02,0x06,0x09,0x0D,0x08,0x0C,0x0B,0x0F,0x0A,0x0E
    .byte 0x08,0x09,0x0C,0x0D,0x00,0x01,0x04,0x05,0x0A,0x0B,0x0E,0x0F,0x02,0x03,0x06,0x07
    .byte 0x0C,0x08,0x0D,0x09,0x04,0x00,0x05,0x01,0x0E,0x0A,0x0F,0x0B,0x06,0x02,0x07,0x03
    .byte 0x0D,0x0C,0x09,0x08,0x05,0x04,0x01,0x00,0x0F,0x0E,0x0B,0x0A,0x07,0x06,0x03,0x02
    .byte 0x09,0x0D,0x08,0x0C,0x01,0x05,0x00,0x04,0x0B,0x0F,0x0A,0x0E,0x03,0x07,0x02,0x06
    .byte 0x0A,0x0B,0x0E,0x0F,0x08,0x09,0x0C,0x0D,0x02,0x03,0x06,0x07,0x00,0x01,0x04,0x05
    .byte 0x0E,0x0A,0x0F,0x0B,0x0C,0x08,0x0D,0x09,0x06,0x02,0x07,0x03,0x04,0x00,0x05,0x01
    .byte 0x0F,0x0E,0x0B,0x0A,0x0D,0x0C,0x09,0x08,0x07,0x06,0x03,0x02,0x05,0x04,0x01,0x00
    .byte 0x0B,0x0F,0x0A,0x0E,0x09,0x0D,0x08,0x0C,0x03,0x07,0x02,0x06,0x01,0x05,0x00,0x04
    .byte 0x02,0x03,0x06,0x07,0x0A,0x0B,0x0E,0x0F,0x00,0x01,0x04,0x05,0x08,0x09,0x0C,0x0D
    .byte 0x06,0x02,0x07,0x03,0x0E,0x0A,0x0F,0x0B,0x04,0x00,0x05,0x01,0x0C,0x08,0x0D,0x09
    .byte 0x07,0x06,0x03,0x02,0x0F,0x0E,0x0B,0x0A,0x05,0x04,0x01,0x00,0x0D,0x0C,0x09,0x08
    .byte 0x03,0x07,0x02,0x06,0x0B,0x0F,0x0A,0x0E,0x01,0x05,0x00,0x04,0x09,0x0D,0x08,0x0C

 .align 2

 .end
