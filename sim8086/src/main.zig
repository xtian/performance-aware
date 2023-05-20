const std = @import("std");

const Mode = enum(u2) { memory, memory_8bit_displacement, memory_16bit_displacement, register };
const MathOperation = enum(u3) { add = 0b000, sub = 0b101, cmp = 0b111 };
const JumpOperation = enum(u8) {
    je = 0b01110100,
    jl = 0b01111100,
    jle = 0b01111110,
    jb = 0b01110010,
    jbe = 0b01110110,
    jp = 0b01111010,
    jo = 0b01110000,
    js = 0b01111000,
    jne = 0b01110101,
    jnl = 0b01111101,
    jnle = 0b01111111,
    jnb = 0b01110011,
    jnbe = 0b01110111,
    jnp = 0b01111011,
    jno = 0b01110001,
    jns = 0b01111001,
    loop = 0b11100010,
    loopz = 0b11100001,
    loopnz = 0b11100000,
    jcxz = 0b11100011,
};

const MathInstruction = packed struct(u8) {
    word: bool,
    swap_direction: bool,
    to_accumulator: bool,
    operation: MathOperation,
    _: u2,
};

const ImmediateMathInstruction = packed struct(u8) {
    word: bool,
    signed: bool,
    _opcode: u6,
};

const MoveInstruction = packed struct(u8) {
    word: bool,
    swap_direction: bool,
    _opcode: u6,
};

const ImmediateToRegisterMoveInstruction = packed struct(u8) {
    reg: u3,
    word: bool,
    _opcode: u4,
};

const InstructionExtra = packed struct(u8) {
    rm: u3,
    reg: u3,
    mode: Mode,
};

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();

    const filename = args.next() orelse return std.debug.print("usage: sim8086 [file]\n", .{});
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const reader = file.reader();
    const writer = std.io.getStdOut().writer();

    try writer.print("; {s}\n\n", .{filename});
    try writer.print("bits 16\n\n", .{});

    var buf: [64]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    while (reader.readIntNative(u8)) |byte| {
        fba.reset();

        if (byte >> 4 == 0b00000111 or byte >> 4 == 0b00001110) {
            const operation = @intToEnum(JumpOperation, byte);
            const data = try reader.readIntNative(i8);

            try writer.print("{s} ($+2)+{}\n", .{ jumpOperation(operation), data });
            continue;
        }

        if (byte >> 4 == 0b00001011) {
            const instruction = @bitCast(ImmediateToRegisterMoveInstruction, byte);
            const data = try readImmediate(reader, instruction.word);
            const register = try registerName(allocator, instruction.reg, instruction.word);

            try writer.print("mov {s}, {}\n", .{ register, data });
            continue;
        }

        if (byte >> 2 == 0b00100010) {
            const instruction = @bitCast(MoveInstruction, byte);
            const extra = try reader.readStruct(InstructionExtra);
            const displacement = try readDisplacement(reader, extra.mode, extra.rm);
            const operands = try getOperands(
                allocator,
                instruction.word,
                instruction.swap_direction,
                displacement,
                extra,
            );

            try writer.print("mov {s}, {s}\n", .{ operands.left, operands.right });
            continue;
        }

        if (byte >> 2 == 0b00100000) {
            const instruction = @bitCast(ImmediateMathInstruction, byte);
            const extra = try reader.readStruct(InstructionExtra);
            const displacement = try readDisplacement(reader, extra.mode, extra.rm);

            const data = if (!instruction.signed and instruction.word)
                try reader.readIntNative(u16)
            else
                try reader.readIntNative(u8);

            const annotation = if (extra.mode == .register)
                ""
            else if (instruction.word) "word " else "byte ";

            try writer.print("{s} {s}{s}, {}\n", .{
                mathOperation(@intToEnum(MathOperation, extra.reg)),
                annotation,
                try operandValue(allocator, instruction.word, displacement, extra),
                data,
            });
            continue;
        }

        const instruction = @bitCast(MathInstruction, byte);

        if (instruction.to_accumulator) {
            const data = try readImmediate(reader, instruction.word);

            try writer.print("{s} {s}, {}\n", .{
                mathOperation(instruction.operation),
                if (instruction.word) "ax" else "al",
                data,
            });
            continue;
        }

        const extra = try reader.readStruct(InstructionExtra);
        const displacement = try readDisplacement(reader, extra.mode, extra.rm);

        const operands = try getOperands(
            allocator,
            instruction.word,
            instruction.swap_direction,
            displacement,
            extra,
        );

        try writer.print("{s} {s}, {s}\n", .{ mathOperation(instruction.operation), operands.left, operands.right });
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => std.debug.print("Error reading instruction: {}\n", .{err}),
    }
}

fn readDisplacement(reader: anytype, mode: Mode, rm: u3) !u16 {
    return switch (mode) {
        .memory => if (rm == 0b110) try reader.readIntNative(u16) else 0,
        .memory_8bit_displacement => try reader.readIntNative(u8),
        .memory_16bit_displacement => try reader.readIntNative(u16),
        .register => 0,
    };
}

fn readImmediate(reader: anytype, word: bool) !u16 {
    return if (word) try reader.readIntNative(u16) else try reader.readIntNative(u8);
}

fn jumpOperation(value: JumpOperation) []const u8 {
    return switch (value) {
        .je => "je",
        .jl => "jl",
        .jle => "jle",
        .jb => "jb",
        .jbe => "jbe",
        .jp => "jp",
        .jo => "jo",
        .js => "js",
        .jne => "jne",
        .jnl => "jnl",
        .jnle => "jnle",
        .jnb => "jnb",
        .jnbe => "jnbe",
        .jnp => "jnp",
        .jno => "jno",
        .jns => "jns",
        .loop => "loop",
        .loopz => "loopz",
        .loopnz => "loopnz",
        .jcxz => "jcxz",
    };
}

fn mathOperation(value: MathOperation) []const u8 {
    return switch (value) {
        .add => "add",
        .sub => "sub",
        .cmp => "cmp",
    };
}

const Operands = struct { left: []u8, right: []u8 };

fn getOperands(
    allocator: std.mem.Allocator,
    word: bool,
    swap_direction: bool,
    displacement: u16,
    extra: InstructionExtra,
) !Operands {
    const register = try registerName(allocator, extra.reg, word);

    if (extra.mode == .register) {
        return .{ .left = try registerName(allocator, extra.rm, word), .right = register };
    }

    const operand = try operandValue(allocator, word, displacement, extra);

    return if (swap_direction)
        .{ .left = register, .right = operand }
    else
        .{ .left = operand, .right = register };
}

fn operandValue(allocator: std.mem.Allocator, word: bool, displacement: u16, extra: InstructionExtra) ![]u8 {
    if (extra.mode == .register) {
        return try registerName(allocator, extra.rm, word);
    } else if (extra.mode == .memory and extra.rm == 0b110) {
        return try std.fmt.allocPrint(allocator, "[{}]", .{displacement});
    } else {
        const left = switch (extra.rm) {
            0b000 => "bx + si",
            0b001 => "bx + di",
            0b010 => "bp + si",
            0b011 => "bp + di",
            0b100 => "si",
            0b101 => "di",
            0b110 => "bp",
            0b111 => "bx",
        };

        const right = if (displacement > 0)
            try std.fmt.allocPrint(allocator, " + {}", .{displacement})
        else
            "";

        return try std.fmt.allocPrint(allocator, "[{s}{s}]", .{ left, right });
    }
}

fn registerName(allocator: std.mem.Allocator, register: u3, word: bool) ![]u8 {
    var left: []const u8 = undefined;
    var right: []const u8 = undefined;

    if (word) {
        left = switch (register) {
            0b000 => "a",
            0b001 => "c",
            0b010 => "d",
            0b011 => "b",
            0b100 => "s",
            0b101 => "b",
            0b110 => "s",
            0b111 => "d",
        };

        right = switch (register) {
            0b000, 0b001, 0b010, 0b011 => "x",
            0b100, 0b101 => "p",
            0b110, 0b111 => "i",
        };
    } else {
        left = switch (register) {
            0b000, 0b100 => "a",
            0b001, 0b101 => "c",
            0b010, 0b110 => "d",
            0b011, 0b111 => "b",
        };

        right = if (register < 0b100) "l" else "h";
    }

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ left, right });
}
