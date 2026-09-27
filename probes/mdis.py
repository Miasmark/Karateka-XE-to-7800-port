import sys

# minimal 6502 opcode table: mode -> (len, mnemonic)
OP = {
0x00:(1,"BRK"),0x01:(2,"ORA (zp,X)"),0x05:(2,"ORA zp"),0x06:(2,"ASL zp"),0x08:(1,"PHP"),
0x09:(2,"ORA #"),0x0A:(1,"ASL A"),0x0D:(3,"ORA abs"),0x0E:(3,"ASL abs"),
0x10:(2,"BPL"),0x11:(2,"ORA (zp),Y"),0x15:(2,"ORA zp,X"),0x16:(2,"ASL zp,X"),0x18:(1,"CLC"),
0x19:(3,"ORA abs,Y"),0x1D:(3,"ORA abs,X"),0x1E:(3,"ASL abs,X"),
0x20:(3,"JSR"),0x21:(2,"AND (zp,X)"),0x24:(2,"BIT zp"),0x25:(2,"AND zp"),0x26:(2,"ROL zp"),
0x28:(1,"PLP"),0x29:(2,"AND #"),0x2A:(1,"ROL A"),0x2C:(3,"BIT abs"),0x2D:(3,"AND abs"),
0x2E:(3,"ROL abs"),
0x30:(2,"BMI"),0x31:(2,"AND (zp),Y"),0x35:(2,"AND zp,X"),0x36:(2,"ROL zp,X"),0x38:(1,"SEC"),
0x39:(3,"AND abs,Y"),0x3D:(3,"AND abs,X"),0x3E:(3,"ROL abs,X"),
0x40:(1,"RTI"),0x41:(2,"EOR (zp,X)"),0x45:(2,"EOR zp"),0x46:(2,"LSR zp"),0x48:(1,"PHA"),
0x49:(2,"EOR #"),0x4A:(1,"LSR A"),0x4C:(3,"JMP"),0x4D:(3,"EOR abs"),0x4E:(3,"LSR abs"),
0x50:(2,"BVC"),0x51:(2,"EOR (zp),Y"),0x55:(2,"EOR zp,X"),0x56:(2,"LSR zp,X"),0x58:(1,"CLI"),
0x59:(3,"EOR abs,Y"),0x5D:(3,"EOR abs,X"),0x5E:(3,"LSR abs,X"),
0x60:(1,"RTS"),0x61:(2,"ADC (zp,X)"),0x65:(2,"ADC zp"),0x66:(2,"ROR zp"),0x68:(1,"PLA"),
0x69:(2,"ADC #"),0x6A:(1,"ROR A"),0x6C:(3,"JMP (") ,0x6D:(3,"ADC abs"),0x6E:(3,"ROR abs"),
0x70:(2,"BVS"),0x71:(2,"ADC (zp),Y"),0x75:(2,"ADC zp,X"),0x76:(2,"ROR zp,X"),0x78:(1,"SEI"),
0x79:(3,"ADC abs,Y"),0x7D:(3,"ADC abs,X"),0x7E:(3,"ROR abs,X"),
0x81:(2,"STA (zp,X)"),0x84:(2,"STY zp"),0x85:(2,"STA zp"),0x86:(2,"STX zp"),0x88:(1,"DEY"),
0x8A:(1,"TXA"),0x8C:(3,"STY abs"),0x8D:(3,"STA abs"),0x8E:(3,"STX abs"),
0x90:(2,"BCC"),0x91:(2,"STA (zp),Y"),0x94:(2,"STY zp,X"),0x95:(2,"STA zp,X"),0x96:(2,"STX zp,Y"),
0x98:(1,"TYA"),0x99:(3,"STA abs,Y"),0x9A:(1,"TXS"),0x9D:(3,"STA abs,X"),
0xA0:(2,"LDY #"),0xA1:(2,"LDA (zp,X)"),0xA2:(2,"LDX #"),0xA4:(2,"LDY zp"),0xA5:(2,"LDA zp"),
0xA6:(2,"LDX zp"),0xA8:(1,"TAY"),0xA9:(2,"LDA #"),0xAA:(1,"TAX"),0xAC:(3,"LDY abs"),
0xAD:(3,"LDA abs"),0xAE:(3,"LDX abs"),
0xB0:(2,"BCS"),0xB1:(2,"LDA (zp),Y"),0xB4:(2,"LDY zp,X"),0xB5:(2,"LDA zp,X"),0xB6:(2,"LDX zp,Y"),
0xB8:(1,"CLV"),0xB9:(3,"LDA abs,Y"),0xBA:(1,"TSX"),0xBC:(3,"LDY abs,X"),0xBD:(3,"LDA abs,X"),
0xBE:(3,"LDX abs,Y"),
0xC0:(2,"CPY #"),0xC1:(2,"CMP (zp,X)"),0xC4:(2,"CPY zp"),0xC5:(2,"CMP zp"),0xC6:(2,"DEC zp"),
0xC8:(1,"INY"),0xC9:(2,"CMP #"),0xCA:(1,"DEX"),0xCC:(3,"CPY abs"),0xCD:(3,"CMP abs"),
0xCE:(3,"DEC abs"),
0xD0:(2,"BNE"),0xD1:(2,"CMP (zp),Y"),0xD5:(2,"CMP zp,X"),0xD6:(2,"DEC zp,X"),0xD8:(1,"CLD"),
0xD9:(3,"CMP abs,Y"),0xDD:(3,"CMP abs,X"),0xDE:(3,"DEC abs,X"),
0xE0:(2,"CPX #"),0xE1:(2,"SBC (zp,X)"),0xE4:(2,"CPX zp"),0xE5:(2,"SBC zp"),0xE6:(2,"INC zp"),
0xE8:(1,"INX"),0xE9:(2,"SBC #"),0xEA:(1,"NOP"),0xEC:(3,"CPX abs"),0xED:(3,"SBC abs"),
0xEE:(3,"INC abs"),
0xF0:(2,"BEQ"),0xF1:(2,"SBC (zp),Y"),0xF5:(2,"SBC zp,X"),0xF6:(2,"INC zp,X"),0xF8:(1,"SED"),
0xF9:(3,"SBC abs,Y"),0xFD:(3,"SBC abs,X"),0xFE:(3,"INC abs,X"),
}

def disasm(buf, base, start, count):
    p = start - base
    end = min(p + count, len(buf))
    out = []
    while p < end:
        b = buf[p]
        m = OP.get(b)
        addr = base + p
        if m is None:
            out.append(f"${addr:04X}: DB ${b:02X}")
            p += 1
            continue
        ln, mn = m
        if ln == 3:
            op1, op2 = buf[p+1], buf[p+2]
            arg = op1 | (op2 << 8)
            if mn in ("BPL","BMI","BVC","BVS","BCC","BCS","BNE","BEQ"):
                r = op1 if op1 < 0x80 else op1 - 0x256
                dst = addr + 2 + r
                out.append(f"${addr:04X}: {mn} ${dst:04X}")
            else:
                endb = ")" if mn == "JMP (" else ""
                out.append(f"${addr:04X}: {mn} ${arg:04X}{endb}")
            p += 3
        elif ln == 2:
            out.append(f"${addr:04X}: {mn} ${buf[p+1]:02X}")
            p += 2
        else:
            out.append(f"${addr:04X}: {mn}")
            p += 1
    return "\n".join(out)

if __name__ == "__main__":
    path = sys.argv[1]
    base = int(sys.argv[2], 16)
    start = int(sys.argv[3], 16)
    count = int(sys.argv[4], 16)
    rom = open(path, "rb").read()[128:]
    # bank index derived from CPU address: only bank7 ($C000-$FFFF) fixed
    b7 = rom[7*16384:8*16384]
    print(disasm(b7, 0xC000, start, count))