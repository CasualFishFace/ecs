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
        dense: std.ArrayList(T),
        dense_to_sparse: std.ArrayList(I),

        const Self = @This();

        pub const empty = Self{
            .sparse = .empty,
            .dense = .empty,
            .dense_to_sparse = .empty,
        };

        pub const Error = error{
            Clobbered,
            OutOfMemory,
        };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.dense.deinit(gpa);
            self.sparse.deinit(gpa);
            self.* = undefined;
        }

        pub fn contains(self: *Self, idx: I) bool {
            return idx < self.sparse.items.len and self.sparse.items[idx] != null;
        }

        pub fn dense_index(self: *Self, idx: I) ?I {
            return if (self.contains(idx)) self.sparse.items[idx].? else null;
        }

        pub fn remove(self: *Self, idx: I) ?T {
            const didx = self.dense_index(idx) orelse return null;
            const last_idx = self.dense_to_sparse.getLast();
            const result = self.dense.swapRemove(didx);
            _ = self.dense_to_sparse.swapRemove(didx);
            self.sparse.items[last_idx] = didx;
            self.sparse.items[idx] = null;
            return result;
        }

        pub fn put(self: *Self, gpa: Allocator, idx: I, item: T) Allocator.Error!void {
            if (idx >= self.sparse.items.len) {
                const new_cap = idx + 1;
                try self.sparse.ensureTotalCapacity(gpa, new_cap);
                const slc = self.sparse.unusedCapacitySlice();
                self.sparse.expandToCapacity();
                for (slc) |*x| x.* = null;
            }

            const didx: I = @truncate(self.dense.items.len);
            try self.dense.append(gpa, item);
            try self.dense_to_sparse.append(gpa, idx);
            self.sparse.items[idx] = didx;
        }

        pub fn putNoClobber(self: *Self, gpa: Allocator, idx: I, item: T) Error!void {
            if (self.sparse.items.len <= idx or self.sparse.items[idx]) |_|
                return Error.Clobbered;

            return self.put(gpa, idx, item);
        }
    };
}
