const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const EntityId = @import("entity.zig").EntityId;
const World = @import("world.zig").World;

/// Query for entities with specific component combinations
pub const Query = struct {
    const Self = @This();
    
    /// Component type IDs that entities must have
    with_types: []const u32,
    
    /// Component type IDs that entities must not have
    without_types: []const u32,
    
    /// Initialize a query with required components
    pub fn init(with_types: []const u32) Self {
        return Self{
            .with_types = with_types,
            .without_types = &[_]u32{},
        };
    }
    
    /// Initialize a query with required and excluded components
    pub fn initWithExclusions(with_types: []const u32, without_types: []const u32) Self {
        return Self{
            .with_types = with_types,
            .without_types = without_types,
        };
    }
    
    /// Execute the query and return matching entities
    pub fn execute(self: Self, world: *World, allocator: Allocator) !ArrayList(EntityId) {
        var result = ArrayList(EntityId).init(allocator);
        
        entity_loop: for (world.entities.items) |entity_id| {
            // Check if entity has all required components
            for (self.with_types) |type_id| {
                if (!world.hasComponent(entity_id, type_id)) {
                    continue :entity_loop;
                }
            }
            
            // Check if entity doesn't have any excluded components
            for (self.without_types) |type_id| {
                if (world.hasComponent(entity_id, type_id)) {
                    continue :entity_loop;
                }
            }
            
            try result.append(entity_id);
        }
        
        return result;
    }
};

/// Query iterator for more efficient iteration
pub const QueryIterator = struct {
    const Self = @This();
    
    entities: []const EntityId,
    current_index: usize,
    
    pub fn init(entities: []const EntityId) Self {
        return Self{
            .entities = entities,
            .current_index = 0,
        };
    }
    
    /// Get the next entity in the query results
    pub fn next(self: *Self) ?EntityId {
        if (self.current_index >= self.entities.len) {
            return null;
        }
        
        const entity = self.entities[self.current_index];
        self.current_index += 1;
        return entity;
    }
    
    /// Reset the iterator to the beginning
    pub fn reset(self: *Self) void {
        self.current_index = 0;
    }
    
    /// Get the number of entities in the query
    pub fn count(self: Self) usize {
        return self.entities.len;
    }
};

test "query creation" {
    const type_ids = [_]u32{ 1, 2, 3 };
    const query = Query.init(&type_ids);
    
    try std.testing.expectEqual(@as(usize, 3), query.with_types.len);
    try std.testing.expectEqual(@as(usize, 0), query.without_types.len);
}

test "query with exclusions" {
    const with_types = [_]u32{ 1, 2 };
    const without_types = [_]u32{ 3, 4 };
    const query = Query.initWithExclusions(&with_types, &without_types);
    
    try std.testing.expectEqual(@as(usize, 2), query.with_types.len);
    try std.testing.expectEqual(@as(usize, 2), query.without_types.len);
}

test "query iterator" {
    const entities = [_]EntityId{ 1, 2, 3, 4, 5 };
    var iterator = QueryIterator.init(&entities);
    
    try std.testing.expectEqual(@as(usize, 5), iterator.count());
    
    var count: usize = 0;
    while (iterator.next()) |entity| {
        try std.testing.expect(entity >= 1 and entity <= 5);
        count += 1;
    }
    
    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expectEqual(@as(?EntityId, null), iterator.next());
    
    iterator.reset();
    try std.testing.expectEqual(@as(?EntityId, 1), iterator.next());
}
