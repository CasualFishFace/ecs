This is HEAVILY inspired by the [Bevy](https://bevy.org/) game engine. But using Zig's comptime, I
am able to entirely get rid of the `Query` type that is used in Bevy. The code is quite messy, as
of right now, but I will be documenting it all and refactoring as needed.

This code snippet is subject to change, but as of right now, usage of my ECS looks like this:
```zig
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
        chudlingProc,
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
};

pub const Chudling = struct {
    parent: *Chud,
};

pub fn chudSpawner(ecs: *Ecs, chud: *Chud) !void {
    if (chud.max_children == null or chud.children.size < chud.max_children.?) {
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

pub fn chudlingProc(ecs: *Ecs, id: Ecs.Entity, random: Ecs.Random, chudling: Chudling) !void {
    std.debug.print("I am a chudling :D\n", .{});
    if (random.int(u6) < 32) {
        _ = chudling.parent.children.remove(id);
        _ = ecs.removeEntity(id);
    }
}
```

Output:
```
I am a chud and I have 1 chudling :D
I am a chudling :D
I am a chud and I have 2 chudlings :D
I am a chudling :D
I am a chudling :D
I am a chud and I have 3 chudlings :D
I am a chudling :D
I am a chudling :D
I am a chudling :D
I am a chud and I have 3 chudlings :D
I am a chudling :D
I am a chudling :D
I am a chudling :D
```
