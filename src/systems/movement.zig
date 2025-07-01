const std = @import("std");
const World = @import("../core/world.zig").World;
const Position = @import("../components/spatial.zig").Position;
const Velocity = @import("../components/spatial.zig").Velocity;
const getPositionTypeId = @import("../components/spatial.zig").getPositionTypeId;
const getVelocityTypeId = @import("../components/spatial.zig").getVelocityTypeId;

/// System that applies velocity to position
pub fn movementSystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Get all entities with both position and velocity
    const pos_type_id = getPositionTypeId();
    const vel_type_id = getVelocityTypeId();
    
    var entities_with_position = try world.getEntitiesWithComponent(pos_type_id, allocator);
    defer entities_with_position.deinit();
    
    for (entities_with_position.items) |entity_id| {
        const pos_component = world.getComponent(entity_id, pos_type_id);
        const vel_component = world.getComponent(entity_id, vel_type_id);
        
        if (pos_component != null and vel_component != null) {
            const position = Position.fromComponent(pos_component.?);
            const velocity = Velocity.fromComponent(vel_component.?);
            
            // Apply velocity to position
            position.translate(velocity.dx * dt, velocity.dy * dt);
        }
    }
}

/// System that updates velocities (can be used for physics, drag, etc.)
pub fn velocitySystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const vel_type_id = getVelocityTypeId();
    var entities_with_velocity = try world.getEntitiesWithComponent(vel_type_id, allocator);
    defer entities_with_velocity.deinit();
    
    for (entities_with_velocity.items) |entity_id| {
        const vel_component = world.getComponent(entity_id, vel_type_id);
        if (vel_component) |component| {
            const velocity = Velocity.fromComponent(component);
            
            // Apply simple drag/friction (reduce velocity by 1% per second)
            const drag_factor = 0.99;
            const drag_this_frame = std.math.pow(f32, drag_factor, dt);
            velocity.scale(drag_this_frame);
            
            // Stop very small velocities to prevent infinite tiny movements
            if (velocity.magnitude() < 0.01) {
                velocity.set(0, 0);
            }
        }
    }
}
