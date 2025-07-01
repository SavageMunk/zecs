const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// Entity ID type - simple integer for now
pub const EntityId = u32;

/// Invalid entity constant
pub const INVALID_ENTITY: EntityId = 0;

/// Component interface - all components must implement this
pub const Component = struct {
    const Self = @This();
    
    /// Component type ID for runtime type checking
    type_id: u32,
    
    /// Virtual function table for component operations
    vtable: *const VTable,
    
    pub const VTable = struct {
        destroy: *const fn (self: *Component, allocator: Allocator) void,
        clone: *const fn (self: *Component, allocator: Allocator) *Component,
    };
    
    pub fn destroy(self: *Component, allocator: Allocator) void {
        self.vtable.destroy(self, allocator);
    }
    
    pub fn clone(self: *Component, allocator: Allocator) *Component {
        return self.vtable.clone(self, allocator);
    }
};

/// ECS World - manages entities, components, and systems
pub const World = struct {
    const Self = @This();
    
    allocator: Allocator,
    next_entity_id: EntityId,
    
    /// Entity storage - sparse set for efficient iteration
    entities: ArrayList(EntityId),
    
    /// Component storage - maps entity ID to components
    components: std.HashMap(EntityId, ArrayList(*Component), std.hash_map.AutoContext(EntityId), std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .next_entity_id = 1, // Start from 1, reserve 0 as invalid
            .entities = ArrayList(EntityId).init(allocator),
            .components = std.HashMap(EntityId, ArrayList(*Component), std.hash_map.AutoContext(EntityId), std.hash_map.default_max_load_percentage).init(allocator),
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
    }
    
    /// Create a new entity
    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        
        try self.entities.append(entity_id);
        try self.components.put(entity_id, ArrayList(*Component).init(self.allocator));
        
        return entity_id;
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
    
    /// Add a component to an entity
    pub fn addComponent(self: *Self, entity_id: EntityId, component: *Component) !void {
        if (self.components.getPtr(entity_id)) |component_list| {
            try component_list.append(component);
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
    
    /// Print world state for debugging
    pub fn debugPrint(self: *Self) void {
        print("World State:\n", .{});
        print("  Entities: {d}\n", .{self.entities.items.len});
        print("  Next Entity ID: {d}\n", .{self.next_entity_id});
        
        for (self.entities.items) |entity_id| {
            if (self.components.get(entity_id)) |component_list| {
                print("  Entity {d}: {d} components\n", .{ entity_id, component_list.items.len });
            }
        }
    }
};

/// Example Position Component
pub const PositionComponent = struct {
    const Self = @This();
    const TYPE_ID: u32 = 1;
    
    component: Component,
    x: f32,
    y: f32,
    
    pub fn init(x: f32, y: f32, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .component = Component{
                .type_id = TYPE_ID,
                .vtable = &vtable,
            },
            .x = x,
            .y = y,
        };
        return self;
    }
    
    const vtable = Component.VTable{
        .destroy = destroy,
        .clone = clone,
    };
    
    fn destroy(component: *Component, allocator: Allocator) void {
        const self: *Self = @fieldParentPtr("component", component);
        allocator.destroy(self);
    }
    
    fn clone(component: *Component, allocator: Allocator) *Component {
        const self: *Self = @fieldParentPtr("component", component);
        const new_component = Self.init(self.x, self.y, allocator) catch unreachable;
        return &new_component.component;
    }
    
    pub fn getPosition(component: *Component) struct { x: f32, y: f32 } {
        const self: *Self = @fieldParentPtr("component", component);
        return .{ .x = self.x, .y = self.y };
    }
    
    pub fn setPosition(component: *Component, x: f32, y: f32) void {
        const self: *Self = @fieldParentPtr("component", component);
        self.x = x;
        self.y = y;
    }
};

/// Example Velocity Component
pub const VelocityComponent = struct {
    const Self = @This();
    const TYPE_ID: u32 = 2;
    
    component: Component,
    dx: f32,
    dy: f32,
    
    pub fn init(dx: f32, dy: f32, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .component = Component{
                .type_id = TYPE_ID,
                .vtable = &vtable,
            },
            .dx = dx,
            .dy = dy,
        };
        return self;
    }
    
    const vtable = Component.VTable{
        .destroy = destroy,
        .clone = clone,
    };
    
    fn destroy(component: *Component, allocator: Allocator) void {
        const self: *Self = @fieldParentPtr("component", component);
        allocator.destroy(self);
    }
    
    fn clone(component: *Component, allocator: Allocator) *Component {
        const self: *Self = @fieldParentPtr("component", component);
        const new_component = Self.init(self.dx, self.dy, allocator) catch unreachable;
        return &new_component.component;
    }
    
    pub fn getVelocity(component: *Component) struct { dx: f32, dy: f32 } {
        const self: *Self = @fieldParentPtr("component", component);
        return .{ .dx = self.dx, .dy = self.dy };
    }
    
    pub fn setVelocity(component: *Component, dx: f32, dy: f32) void {
        const self: *Self = @fieldParentPtr("component", component);
        self.dx = dx;
        self.dy = dy;
    }
};

/// System for updating positions based on velocity
pub fn movementSystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Get all entities with both position and velocity components
    var entities_with_position = try world.getEntitiesWithComponent(PositionComponent.TYPE_ID, allocator);
    defer entities_with_position.deinit();
    
    for (entities_with_position.items) |entity_id| {
        const position_comp = world.getComponent(entity_id, PositionComponent.TYPE_ID);
        const velocity_comp = world.getComponent(entity_id, VelocityComponent.TYPE_ID);
        
        if (position_comp != null and velocity_comp != null) {
            const pos = PositionComponent.getPosition(position_comp.?);
            const vel = VelocityComponent.getVelocity(velocity_comp.?);
            
            // Update position based on velocity
            PositionComponent.setPosition(position_comp.?, pos.x + vel.dx * dt, pos.y + vel.dy * dt);
        }
    }
}

/// Demo function showing basic ECS usage
pub fn demo() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create world
    var world = World.init(allocator);
    defer world.deinit();
    
    print("=== ZECS Demo ===\n\n", .{});
    
    // Create some entities
    const entity1 = try world.createEntity();
    const entity2 = try world.createEntity();
    const entity3 = try world.createEntity();
    
    print("Created entities: {d}, {d}, {d}\n", .{ entity1, entity2, entity3 });
    
    // Add components
    const pos1 = try PositionComponent.init(10.0, 20.0, allocator);
    const vel1 = try VelocityComponent.init(1.0, 0.5, allocator);
    
    const pos2 = try PositionComponent.init(0.0, 0.0, allocator);
    const vel2 = try VelocityComponent.init(-0.5, 1.0, allocator);
    
    const pos3 = try PositionComponent.init(5.0, 5.0, allocator);
    // Entity 3 has position but no velocity
    
    try world.addComponent(entity1, &pos1.component);
    try world.addComponent(entity1, &vel1.component);
    
    try world.addComponent(entity2, &pos2.component);
    try world.addComponent(entity2, &vel2.component);
    
    try world.addComponent(entity3, &pos3.component);
    
    print("Added components to entities\n", .{});
    
    // Print initial state
    print("\nInitial positions:\n", .{});
    for ([_]EntityId{ entity1, entity2, entity3 }) |entity_id| {
        if (world.getComponent(entity_id, PositionComponent.TYPE_ID)) |pos_comp| {
            const pos = PositionComponent.getPosition(pos_comp);
            print("  Entity {d}: ({d:.2}, {d:.2})\n", .{ entity_id, pos.x, pos.y });
        }
    }
    
    // Run movement system for a few frames
    print("\nRunning movement system...\n", .{});
    for (0..5) |frame| {
        try movementSystem(&world, 0.1); // 0.1 second time step
        
        print("Frame {d}:\n", .{frame + 1});
        for ([_]EntityId{ entity1, entity2, entity3 }) |entity_id| {
            if (world.getComponent(entity_id, PositionComponent.TYPE_ID)) |pos_comp| {
                const pos = PositionComponent.getPosition(pos_comp);
                print("  Entity {d}: ({d:.2}, {d:.2})\n", .{ entity_id, pos.x, pos.y });
            }
        }
    }
    
    // Debug world state
    print("\n", .{});
    world.debugPrint();
}

pub fn main() !void {
    try demo();
}

// Tests
test "Entity creation and destruction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var world = World.init(allocator);
    defer world.deinit();
    
    const entity = try world.createEntity();
    try std.testing.expect(entity != INVALID_ENTITY);
    try std.testing.expect(world.entities.items.len == 1);
    
    world.destroyEntity(entity);
    try std.testing.expect(world.entities.items.len == 0);
}

test "Component addition and retrieval" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var world = World.init(allocator);
    defer world.deinit();
    
    const entity = try world.createEntity();
    const pos = try PositionComponent.init(1.0, 2.0, allocator);
    
    try world.addComponent(entity, &pos.component);
    
    const retrieved = world.getComponent(entity, PositionComponent.TYPE_ID);
    try std.testing.expect(retrieved != null);
    
    const position = PositionComponent.getPosition(retrieved.?);
    try std.testing.expect(position.x == 1.0);
    try std.testing.expect(position.y == 2.0);
}
