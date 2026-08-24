const std = @import("std");
const Allocator = std.mem.Allocator;

const Ecs = @import("Ecs.zig");

pub fn SparseSet(comptime I: type, comptime T: type) type {
    const errstring = "expected an unsigned integer of type `usize` or smaller";

    switch (@typeInfo(I)) {
        .int => |info| {
            if (info.signedness == .signed or info.bits > @bitSizeOf(usize))
                @compileError(errstring);
        },
        else => @compileError(errstring),
    }

    return struct {
        sparse: std.ArrayList(?I),
        dense: std.MultiArrayList(struct {
            item: T,
            idx: Ecs.Entity,
        }),

        const Self = @This();

        pub const empty = Self{
            .sparse = .empty,
            .dense = .empty,
        };

        pub const Error = error{
            Clobbered,
        };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.dense.deinit(gpa);
            self.sparse.deinit(gpa);
            self.* = undefined;
        }

        pub fn remove(self: *Self, idx: I) ?T {
            if (idx > self.sparse.items.len) return null;
            const didx = self.sparse.items[idx] orelse return null;
            const slc = self.dense.slice();
            const sidx: Ecs.Entity = slc.items(.idx)[self.dense.len - 1];
            const removed = slc.items(.item)[didx];
            self.dense.swapRemove(didx);
            self.sparse.items[idx] = null;
            self.sparse.items[sidx] = didx;
            return removed;
        }

        pub fn put(self: *Self, gpa: Allocator, idx: I, item: T) !void {
            if (idx >= self.sparse.items.len) {
                const new_cap = idx + 1;
                try self.sparse.ensureTotalCapacity(gpa, new_cap);
                const slc = self.sparse.unusedCapacitySlice();
                self.sparse.expandToCapacity();
                for (slc) |*x| x.* = null;
            }

            const didx: I = @truncate(self.dense.len);
            try self.dense.append(gpa, .{ .idx = idx, .item = item });
            self.sparse.items[idx] = didx;
        }

        pub fn putNoClobber(self: *Self, gpa: Allocator, idx: I, item: T) !void {
            if (self.sparse.items.len <= idx or self.sparse.items[idx]) |_|
                return Error.Clobbered;

            return self.put(gpa, idx, item);
        }
    };
}
