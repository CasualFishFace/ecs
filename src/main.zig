const std = @import("std");
const Ecs = @import("Ecs.zig");

pub fn main(init: std.process.Init) !void {
    var ecs = Ecs.init(init.gpa, .{});
    defer ecs.deinit();

    _ = try ecs.addEntity(.{
        Chud.maxChildren(3),
    });

    try ecs.addSystems(.{
        Chud.spawner,
        Chudling.proc,
    });

    try ecs.run();
}

pub const Chud = struct {
    children: std.AutoHashMapUnmanaged(Ecs.Entity, void),
    max_children: ?Ecs.Entity,

    pub fn maxChildren(max_children: ?Ecs.Entity) @This() {
        return .{
            .children = .empty,
            .max_children = max_children,
        };
    }

    // If your object needs to be deinitialized, make sure to include the method directly inside
    // its declarations
    pub fn deinit(self: *@This(), ecs: *Ecs) void {
        var it = self.children.keyIterator();
        while (it.next()) |child| {
            _ = ecs.removeEntity(child.*);
            _ = self.children.remove(child.*);
        }

        self.children.deinit(ecs.allocator);
        self.* = undefined;
    }

    pub fn spawner(chud: *Chud, ecs: *Ecs, random: Ecs.Random) !void {
        if ((chud.max_children == null or
            chud.children.size < chud.max_children.?) and
            random.int(u1) == 0)
        {
            const child = try ecs.addEntity(.{Chudling{
                .parent = chud,
            }});

            try chud.children.put(ecs.allocator, child, {});
        }

        switch (chud.children.size) {
            0 => std.debug.print("I am a chud with no chudlings :(\n", .{}),
            1 => std.debug.print("I am a chud and I have 1 chudling :D\n", .{}),
            else => std.debug.print("I am a chud and I have {} chudlings :D\n", .{
                chud.children.size,
            }),
        }
    }
};

pub const Chudling = struct {
    parent: *Chud,

    pub fn proc(chudling: Chudling, ecs: *Ecs, id: Ecs.Entity, random: Ecs.Random) !void {
        std.debug.print("I am a chudling :D\n", .{});
        if (random.int(u6) < 32) {
            _ = chudling.parent.children.remove(id);
            _ = ecs.removeEntity(id);
        }
    }
};
