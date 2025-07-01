const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

const EntityId = @import("entity.zig").EntityId;
const INVALID_ENTITY = @import("entity.zig").INVALID_ENTITY;
const Component = @import("component.zig").Component;
const System = @import("system.zig").System;
const QuerySystem = @import("fast_query.zig").QuerySystem;

/// ECS World - manages entities, components, and systems
pub const World = struct {
    const Self = @This();
    
    allocator: Allocator,
    next_entity_id: EntityId,
    
    /// Entity storage - sparse set for efficient iteration
    entities: ArrayList(EntityId),
    
    /// Component storage - maps entity ID to components
    components: HashMap(EntityId, ArrayList(*Component), std.hash_map.AutoContext(EntityId), std.hash_map.default_max_load_percentage),
    
    /// System storage and management
    systems: ArrayList(System),
    system_lookup: HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    /// High-performance archetype-based query system
    query_system: ?QuerySystem,
    
    /// World statistics
    tick_count: u64,
    
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .next_entity_id = 1, // Start from 1, reserve 0 as invalid
            .entities = ArrayList(EntityId).init(allocator),
            .components = HashMap(EntityId, ArrayList(*Component), std.hash_map.AutoContext(EntityId), std.hash_map.default_max_load_percentage).init(allocator),
            .systems = ArrayList(System).init(allocator),
            .system_lookup = HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .query_system = QuerySystem.init(allocator),
            .tick_count = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up all components
        var iterator = self.components.iterator();
        while (iterator.next()) |entry| {
            var component_list = entry.value_ptr;
            for (component_list.items) |component| {
                component.destroy(self.allocator);
            }
            component_list.deinit();
        }
        
        self.components.deinit();
        self.entities.deinit();
        self.systems.deinit();
        self.system_lookup.deinit();
        
        if (self.query_system) |*query_sys| {
            query_sys.deinit();
        }
    }
    
    // === Entity Management ===
    
    /// Create a new entity
    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        
        try self.entities.append(entity_id);
        try self.components.put(entity_id, ArrayList(*Component).init(self.allocator));
        
        return entity_id;
    }
    
    /// Create multiple entities at once
    pub fn createEntities(self: *Self, count: u32) ![]EntityId {
        const entity_ids = try self.allocator.alloc(EntityId, count);
        
        for (entity_ids, 0..) |*entity_id, i| {
            entity_id.* = try self.createEntity();
            _ = i; // Suppress unused variable warning
        }
        
        return entity_ids;
    }
    
    /// Destroy an entity and all its components
    pub fn destroyEntity(self: *Self, entity_id: EntityId) void {
        // Remove from entities list
        for (self.entities.items, 0..) |id, i| {
            if (id == entity_id) {
                _ = self.entities.swapRemove(i);
                break;
            }
        }
        
        // Clean up components
        if (self.components.get(entity_id)) |component_list| {
            for (component_list.items) |component| {
                component.destroy(self.allocator);
            }
        }
        
        // Remove from components map
        if (self.components.getPtr(entity_id)) |component_list| {
            component_list.deinit();
            _ = self.components.remove(entity_id);
        }
    }
    
    /// Destroy multiple entities
    pub fn destroyEntities(self: *Self, entity_ids: []const EntityId) void {
        for (entity_ids) |entity_id| {
            self.destroyEntity(entity_id);
        }
    }
    
    /// Check if an entity exists
    pub fn hasEntity(self: *Self, entity_id: EntityId) bool {
        for (self.entities.items) |id| {
            if (id == entity_id) return true;
        }
        return false;
    }
    
    // === Component Management ===
    
    /// Add a component to an entity
    pub fn addComponent(self: *Self, entity_id: EntityId, component: *Component) !void {
        if (self.components.getPtr(entity_id)) |component_list| {
            try component_list.append(component);
        } else {
            return error.EntityNotFound;
        }
    }
    
    /// Get a component from an entity by type ID
    pub fn getComponent(self: *Self, entity_id: EntityId, type_id: u32) ?*Component {
        if (self.components.get(entity_id)) |component_list| {
            for (component_list.items) |component| {
                if (component.type_id == type_id) {
                    return component;
                }
            }
        }
        return null;
    }
    
    /// Remove a component from an entity by type ID
    pub fn removeComponent(self: *Self, entity_id: EntityId, type_id: u32) bool {
        if (self.components.getPtr(entity_id)) |component_list| {
            for (component_list.items, 0..) |component, i| {
                if (component.type_id == type_id) {
                    component.destroy(self.allocator);
                    _ = component_list.swapRemove(i);
                    return true;
                }
            }
        }
        return false;
    }
    
    /// Check if an entity has a component of a specific type
    pub fn hasComponent(self: *Self, entity_id: EntityId, type_id: u32) bool {
        return self.getComponent(entity_id, type_id) != null;
    }
    
    /// Get all entities that have a specific component type
    pub fn getEntitiesWithComponent(self: *Self, type_id: u32, allocator: Allocator) !ArrayList(EntityId) {
        var result = ArrayList(EntityId).init(allocator);
        
        for (self.entities.items) |entity_id| {
            if (self.getComponent(entity_id, type_id) != null) {
                try result.append(entity_id);
            }
        }
        
        return result;
    }
    
    /// Get all entities that have ALL of the specified component types
    pub fn getEntitiesWithComponents(self: *Self, type_ids: []const u32, allocator: Allocator) !ArrayList(EntityId) {
        var result = ArrayList(EntityId).init(allocator);
        
        entity_loop: for (self.entities.items) |entity_id| {
            // Check if entity has all required components
            for (type_ids) |type_id| {
                if (!self.hasComponent(entity_id, type_id)) {
                    continue :entity_loop;
                }
            }
            try result.append(entity_id);
        }
        
        return result;
    }
    
    // === System Management ===
    
    /// Add a system to the world
    pub fn addSystem(self: *Self, system: System) !void {
        const index = self.systems.items.len;
        try self.systems.append(system);
        try self.system_lookup.put(system.name, index);
    }
    
    /// Remove a system by name
    pub fn removeSystem(self: *Self, name: []const u8) bool {
        if (self.system_lookup.get(name)) |index| {
            _ = self.systems.swapRemove(index);
            _ = self.system_lookup.remove(name);
            
            // Update indices in lookup table
            if (index < self.systems.items.len) {
                const moved_system = &self.systems.items[index];
                self.system_lookup.put(moved_system.name, index) catch {};
            }
            
            return true;
        }
        return false;
    }
    
    /// Update all systems
    pub fn update(self: *Self, dt: f32) !void {
        self.tick_count += 1;
        
        // Sort systems by priority (higher priority runs first)
        const SystemSorter = struct {
            fn lessThan(context: void, a: System, b: System) bool {
                _ = context;
                return a.priority > b.priority;
            }
        };
        
        std.mem.sort(System, self.systems.items, {}, SystemSorter.lessThan);
        
        // Execute all enabled systems
        for (self.systems.items) |*system| {
            if (system.enabled) {
                try system.update(self, dt);
            }
        }
    }
    
    /// Update a specific system by name
    pub fn updateSystem(self: *Self, name: []const u8, dt: f32) !void {
        if (self.system_lookup.get(name)) |index| {
            const system = &self.systems.items[index];
            if (system.enabled) {
                try system.update(self, dt);
            }
        }
    }
    
    // === World Statistics ===
    
    /// Get the current tick count
    pub fn getTick(self: *Self) u64 {
        return self.tick_count;
    }
    
    /// Get the number of entities
    pub fn getEntityCount(self: *Self) usize {
        return self.entities.items.len;
    }
    
    /// Get the total number of components across all entities
    pub fn getComponentCount(self: *Self) usize {
        var total: usize = 0;
        var iterator = self.components.iterator();
        while (iterator.next()) |entry| {
            total += entry.value_ptr.items.len;
        }
        return total;
    }
    
    /// Get the number of systems
    pub fn getSystemCount(self: *Self) usize {
        return self.systems.items.len;
    }
    
    /// Print world state for debugging
    pub fn debugPrint(self: *Self) void {
        const print = std.debug.print;
        print("=== World State ===\n", .{});
        print("Tick: {d}\n", .{self.tick_count});
        print("Entities: {d}\n", .{self.getEntityCount()});
        print("Components: {d}\n", .{self.getComponentCount()});
        print("Systems: {d}\n", .{self.getSystemCount()});
        
        print("\nEntities:\n", .{});
        for (self.entities.items) |entity_id| {
            if (self.components.get(entity_id)) |component_list| {
                print("  Entity {d}: {d} components\n", .{ entity_id, component_list.items.len });
            }
        }
        
        print("\nSystems:\n", .{});
        for (self.systems.items) |system| {
            print("  {s}: priority={d}, enabled={}\n", .{ system.name, system.priority, system.enabled });
        }
    }
};

// === Tests ===
test "world creation and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var world = World.init(allocator);
    defer world.deinit();
    
    try std.testing.expectEqual(@as(u64, 0), world.getTick());
    try std.testing.expectEqual(@as(usize, 0), world.getEntityCount());
}

test "entity creation and destruction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var world = World.init(allocator);
    defer world.deinit();
    
    const entity = try world.createEntity();
    try std.testing.expect(entity != INVALID_ENTITY);
    try std.testing.expectEqual(@as(usize, 1), world.getEntityCount());
    try std.testing.expect(world.hasEntity(entity));
    
    world.destroyEntity(entity);
    try std.testing.expectEqual(@as(usize, 0), world.getEntityCount());
    try std.testing.expect(!world.hasEntity(entity));
}

test "bulk entity operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var world = World.init(allocator);
    defer world.deinit();
    
    const entities = try world.createEntities(5);
    defer allocator.free(entities);
    
    try std.testing.expectEqual(@as(usize, 5), world.getEntityCount());
    
    world.destroyEntities(entities);
    try std.testing.expectEqual(@as(usize, 0), world.getEntityCount());
}
