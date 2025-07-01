const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;
const EntityId = @import("entity.zig").EntityId;
const Component = @import("component.zig").Component;
const Archetype = @import("archetype.zig").Archetype;
const QueryResult = @import("archetype.zig").QueryResult;

/// High-performance query system using archetype-based storage
pub const QuerySystem = struct {
    const Self = @This();
    
    /// All archetypes in the world
    archetypes: ArrayList(Archetype),
    
    /// Maps component type combination to archetype index
    archetype_lookup: HashMap(u64, usize, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    
    /// Entity to archetype mapping for fast component updates
    entity_archetype: HashMap(EntityId, usize, std.hash_map.AutoContext(EntityId), std.hash_map.default_max_load_percentage),
    
    /// Cached queries for frequently used patterns
    query_cache: HashMap(u64, QueryResult, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) Self {
        return Self{
            .archetypes = ArrayList(Archetype).init(allocator),
            .archetype_lookup = HashMap(u64, usize, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .entity_archetype = HashMap(EntityId, usize, std.hash_map.AutoContext(EntityId), std.hash_map.default_max_load_percentage).init(allocator),
            .query_cache = HashMap(u64, QueryResult, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.archetypes.items) |*archetype| {
            archetype.deinit();
        }
        self.archetypes.deinit();
        self.archetype_lookup.deinit();
        self.entity_archetype.deinit();
        
        var cache_iter = self.query_cache.iterator();
        while (cache_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.query_cache.deinit();
    }
    
    /// Add entity with components to the appropriate archetype
    pub fn addEntity(self: *Self, entity_id: EntityId, component_types: []const u32, components: []const *Component) !void {
        const archetype_hash = hashComponentTypes(component_types);
        
        // Find or create archetype
        const archetype_index = if (self.archetype_lookup.get(archetype_hash)) |index| 
            index 
        else blk: {
            // Create new archetype
            const new_archetype = try Archetype.init(component_types, self.allocator);
            try self.archetypes.append(new_archetype);
            const index = self.archetypes.items.len - 1;
            try self.archetype_lookup.put(archetype_hash, index);
            break :blk index;
        };
        
        // Add entity to archetype
        const archetype = &self.archetypes.items[archetype_index];
        try archetype.addEntity(entity_id, components);
        try self.entity_archetype.put(entity_id, archetype_index);
        
        // Invalidate query cache since world state changed
        self.invalidateQueryCache();
    }
    
    /// Remove entity from its archetype
    pub fn removeEntity(self: *Self, entity_id: EntityId) void {
        if (self.entity_archetype.get(entity_id)) |archetype_index| {
            var archetype = &self.archetypes.items[archetype_index];
            archetype.removeEntity(entity_id);
            _ = self.entity_archetype.remove(entity_id);
            self.invalidateQueryCache();
        }
    }
    
    /// Query entities with specific component types
    pub fn query(self: *Self, required_types: []const u32) !QueryResult {
        const query_hash = hashComponentTypes(required_types);
        
        // Check cache first
        if (self.query_cache.get(query_hash)) |cached_result| {
            return cached_result;
        }
        
        // Build new query result
        var result = QueryResult.init(self.allocator);
        
        for (self.archetypes.items) |*archetype| {
            if (archetype.matches(required_types)) {
                try result.addArchetype(archetype);
            }
        }
        
        // Cache the result
        try self.query_cache.put(query_hash, result);
        return result;
    }
    
    /// Fast query for common two-component patterns (e.g., Position + Velocity)
    pub fn queryTwo(self: *Self, type_a: u32, type_b: u32) !QueryResult {
        const types = [_]u32{ type_a, type_b };
        return self.query(&types);
    }
    
    /// Fast query for three-component patterns
    pub fn queryThree(self: *Self, type_a: u32, type_b: u32, type_c: u32) !QueryResult {
        const types = [_]u32{ type_a, type_b, type_c };
        return self.query(&types);
    }
    
    /// Get component for specific entity and type
    pub fn getComponent(self: *Self, entity_id: EntityId, type_id: u32) ?*Component {
        if (self.entity_archetype.get(entity_id)) |archetype_index| {
            const archetype = &self.archetypes.items[archetype_index];
            if (archetype.getComponentStorage(type_id)) |storage| {
                // Find entity index in archetype
                if (std.mem.indexOf(EntityId, archetype.entities.items, &[_]EntityId{entity_id})) |entity_index| {
                    if (entity_index < storage.items.len) {
                        return storage.items[entity_index];
                    }
                }
            }
        }
        return null;
    }
    
    /// Update component for entity (assumes component already exists)
    pub fn updateComponent(self: *Self, entity_id: EntityId, type_id: u32, new_component: *Component) bool {
        if (self.entity_archetype.get(entity_id)) |archetype_index| {
            const archetype = &self.archetypes.items[archetype_index];
            if (archetype.getComponentStorage(type_id)) |storage| {
                if (std.mem.indexOf(EntityId, archetype.entities.items, &[_]EntityId{entity_id})) |entity_index| {
                    if (entity_index < storage.items.len) {
                        storage.items[entity_index] = new_component;
                        return true;
                    }
                }
            }
        }
        return false;
    }
    
    /// Invalidate all cached queries
    fn invalidateQueryCache(self: *Self) void {
        var cache_iter = self.query_cache.iterator();
        while (cache_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.query_cache.clearAndFree();
    }
    
    /// Hash function for component type combinations
    fn hashComponentTypes(types: []const u32) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (types) |type_id| {
            hasher.update(std.mem.asBytes(&type_id));
        }
        return hasher.final();
    }
    
    /// Get performance statistics
    pub fn getStats(self: *Self) QueryStats {
        var total_entities: usize = 0;
        for (self.archetypes.items) |*archetype| {
            total_entities += archetype.entities.items.len;
        }
        
        return QueryStats{
            .archetype_count = self.archetypes.items.len,
            .total_entities = total_entities,
            .cached_queries = self.query_cache.count(),
        };
    }
};

/// Performance statistics for the query system
pub const QueryStats = struct {
    archetype_count: usize,
    total_entities: usize,
    cached_queries: usize,
};
