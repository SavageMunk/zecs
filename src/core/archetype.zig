const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;
const EntityId = @import("entity.zig").EntityId;
const Component = @import("component.zig").Component;

/// Archetype represents a unique combination of component types
pub const Archetype = struct {
    const Self = @This();
    
    /// Sorted list of component type IDs that define this archetype
    component_types: []u32,
    
    /// Entities that belong to this archetype
    entities: ArrayList(EntityId),
    
    /// Component storage - arrays of components by type
    /// Each component type has its own densely packed array
    component_storage: HashMap(u32, ArrayList(*Component), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    
    allocator: Allocator,
    
    pub fn init(component_types: []const u32, allocator: Allocator) !Self {
        // Sort component types for consistent archetype identity
        const sorted_types = try allocator.alloc(u32, component_types.len);
        @memcpy(sorted_types, component_types);
        std.mem.sort(u32, sorted_types, {}, comptime std.sort.asc(u32));
        
        var storage = HashMap(u32, ArrayList(*Component), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator);
        
        // Initialize storage arrays for each component type
        for (sorted_types) |type_id| {
            try storage.put(type_id, ArrayList(*Component).init(allocator));
        }
        
        return Self{
            .component_types = sorted_types,
            .entities = ArrayList(EntityId).init(allocator),
            .component_storage = storage,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.component_storage.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.component_storage.deinit();
        self.entities.deinit();
        self.allocator.free(self.component_types);
    }
    
    /// Add an entity with its components to this archetype
    pub fn addEntity(self: *Self, entity_id: EntityId, components: []const *Component) !void {
        if (components.len != self.component_types.len) {
            return error.ComponentCountMismatch;
        }
        
        try self.entities.append(entity_id);
        
        // Add each component to its respective storage array
        for (components, 0..) |component, i| {
            const type_id = self.component_types[i];
            var storage = self.component_storage.getPtr(type_id).?;
            try storage.append(component);
        }
    }
    
    /// Remove an entity from this archetype
    pub fn removeEntity(self: *Self, entity_id: EntityId) void {
        // Find the entity's index
        if (std.mem.indexOf(EntityId, self.entities.items, &[_]EntityId{entity_id})) |index| {
            _ = self.entities.swapRemove(index);
            
            // Remove corresponding components from each storage array
            for (self.component_types) |type_id| {
                var storage = self.component_storage.getPtr(type_id).?;
                _ = storage.swapRemove(index);
            }
        }
    }
    
    /// Get component storage for a specific type
    pub fn getComponentStorage(self: *Self, type_id: u32) ?*ArrayList(*Component) {
        return self.component_storage.getPtr(type_id);
    }
    
    /// Check if this archetype matches the given component types
    pub fn matches(self: *Self, required_types: []const u32) bool {
        for (required_types) |required_type| {
            if (std.mem.indexOf(u32, self.component_types, &[_]u32{required_type}) == null) {
                return false;
            }
        }
        return true;
    }
    
    /// Get archetype signature (for hashing/comparison)
    pub fn getSignature(self: *Self) []const u32 {
        return self.component_types;
    }
};

/// Query result that provides efficient iteration over matching entities
pub const QueryResult = struct {
    const Self = @This();
    
    /// Archetypes that match the query
    matching_archetypes: ArrayList(*Archetype),
    
    /// Current archetype being iterated
    current_archetype_index: usize,
    
    /// Current entity index within current archetype
    current_entity_index: usize,
    
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Self {
        return Self{
            .matching_archetypes = ArrayList(*Archetype).init(allocator),
            .current_archetype_index = 0,
            .current_entity_index = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.matching_archetypes.deinit();
    }
    
    pub fn addArchetype(self: *Self, archetype: *Archetype) !void {
        try self.matching_archetypes.append(archetype);
    }
    
    /// Iterator interface for query results
    pub const Iterator = struct {
        query: *QueryResult,
        
        pub fn next(self: *@This()) ?EntityId {
            while (self.query.current_archetype_index < self.query.matching_archetypes.items.len) {
                const archetype = self.query.matching_archetypes.items[self.query.current_archetype_index];
                
                if (self.query.current_entity_index < archetype.entities.items.len) {
                    const entity = archetype.entities.items[self.query.current_entity_index];
                    self.query.current_entity_index += 1;
                    return entity;
                }
                
                // Move to next archetype
                self.query.current_archetype_index += 1;
                self.query.current_entity_index = 0;
            }
            
            return null;
        }
        
        /// Get components for current entity
        pub fn getComponents(self: *@This(), type_ids: []const u32) ?[]const *Component {
            if (self.query.current_archetype_index >= self.query.matching_archetypes.items.len) {
                return null;
            }
            
            const archetype = self.query.matching_archetypes.items[self.query.current_archetype_index];
            if (self.query.current_entity_index == 0 or self.query.current_entity_index > archetype.entities.items.len) {
                return null;
            }
            
            const entity_index = self.query.current_entity_index - 1;
            var components = std.ArrayList(*Component).init(self.query.allocator);
            
            for (type_ids) |type_id| {
                if (archetype.getComponentStorage(type_id)) |storage| {
                    if (entity_index < storage.items.len) {
                        components.append(storage.items[entity_index]) catch return null;
                    }
                }
            }
            
            return components.toOwnedSlice() catch null;
        }
    };
    
    pub fn iterator(self: *Self) Iterator {
        self.current_archetype_index = 0;
        self.current_entity_index = 0;
        return Iterator{ .query = self };
    }
};
