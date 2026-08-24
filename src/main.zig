const std = @import("std");
const Ecs = @import("Ecs.zig");

pub fn main(init: std.process.Init) !void {
    var ecs = Ecs.init(init.gpa);
    defer ecs.deinit();

    _ = try ecs.addEntity(.{
        Chud.maxChildren(3),
    });

    try ecs.addSystems(.{
        chudSpawner,
        chudling,
    });

    for (0..4) |_| try ecs.step();
}

pub const Chud = struct {
    children: std.ArrayList(Ecs.Entity),
    max_children: ?Ecs.Entity,

    pub fn maxChildren(max_children: ?Ecs.Entity) @This() {
        return .{
            .children = .empty,
            .max_children = max_children,
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.children.deinit(gpa);
        self.* = undefined;
    }
};

pub const Chudling = struct {};

pub fn chudSpawner(ecs: *Ecs, chud: *Chud) !void {
    if (chud.max_children == null or chud.children.items.len < chud.max_children.?) {
        const child = try ecs.addEntity(.{Chudling{}});
        try chud.children.append(ecs.allocator, child);
    }

    switch (chud.children.items.len) {
        0 => std.debug.print("I am a chud with no chudlings :(\n", .{}),
        1 => std.debug.print("I am a chud and I have 1 chudling :D\n", .{}),
        else => std.debug.print("I am a chud and I have {} chudlings :D\n", .{
            chud.children.items.len,
        }),
    }
}

pub fn chudling(_: Chudling) !void {
    std.debug.print("I am a chudling :D\n", .{});
}
