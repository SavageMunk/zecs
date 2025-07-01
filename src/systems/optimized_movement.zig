const std = @import("std");
const World = @import("../core/world.zig").World;
const EntityId = @import("../core/entity.zig").EntityId;
const Position = @import("../components/spatial.zig").Position;
const Velocity = @import("../components/spatial.zig").Velocity;
const getPositionTypeId = @import("../components/spatial.zig").getPositionTypeId;
const getVelocityTypeId = @import("../components/spatial.zig").getVelocityTypeId;

/// High-performance movement system using archetype queries
pub fn optimizedMovementSystem(world: *World, dt: f32) !void {
    const pos_type_id = getPositionTypeId();
    const vel_type_id = getVelocityTypeId();
    
    // Use fast query system if available, otherwise fall back to slower method
    if (world.query_system) |*query_sys| {
        var query_result = try query_sys.queryTwo(pos_type_id, vel_type_id);
        defer query_result.deinit();
        
        var iter = query_result.iterator();
        while (iter.next()) |entity_id| {
            const pos_component = query_sys.getComponent(entity_id, pos_type_id);
            const vel_component = query_sys.getComponent(entity_id, vel_type_id);
            
            if (pos_component != null and vel_component != null) {
                const position = Position.fromComponent(pos_component.?);
                const velocity = Velocity.fromComponent(vel_component.?);
                
                // Apply velocity to position
                position.translate(velocity.dx * dt, velocity.dy * dt);
            }
        }
    } else {
        // Fallback to original method
        return movementSystemFallback(world, dt);
    }
}

/// Original movement system for compatibility
fn movementSystemFallback(world: *World, dt: f32) !void {
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

/// Batch movement system - processes entities in chunks for better cache performance
pub fn batchMovementSystem(world: *World, dt: f32) !void {
    const pos_type_id = getPositionTypeId();
    const vel_type_id = getVelocityTypeId();
    
    if (world.query_system) |*query_sys| {
        var query_result = try query_sys.queryTwo(pos_type_id, vel_type_id);
        defer query_result.deinit();
        
        // Process entities in batches for better cache locality
        const BATCH_SIZE = 64;
        var entities_buffer: [BATCH_SIZE]EntityId = undefined;
        var positions_buffer: [BATCH_SIZE]*Position = undefined;
        var velocities_buffer: [BATCH_SIZE]*Velocity = undefined;
        
        var iter = query_result.iterator();
        var batch_count: usize = 0;
        
        while (iter.next()) |entity_id| {
            const pos_component = query_sys.getComponent(entity_id, pos_type_id);
            const vel_component = query_sys.getComponent(entity_id, vel_type_id);
            
            if (pos_component != null and vel_component != null) {
                entities_buffer[batch_count] = entity_id;
                positions_buffer[batch_count] = Position.fromComponent(pos_component.?);
                velocities_buffer[batch_count] = Velocity.fromComponent(vel_component.?);
                batch_count += 1;
                
                // Process batch when full
                if (batch_count == BATCH_SIZE) {
                    processBatch(positions_buffer[0..batch_count], velocities_buffer[0..batch_count], dt);
                    batch_count = 0;
                }
            }
        }
        
        // Process remaining entities
        if (batch_count > 0) {
            processBatch(positions_buffer[0..batch_count], velocities_buffer[0..batch_count], dt);
        }
    } else {
        return movementSystemFallback(world, dt);
    }
}

/// Process a batch of position/velocity pairs
fn processBatch(positions: []*Position, velocities: []*Velocity, dt: f32) void {
    for (positions, velocities) |pos, vel| {
        pos.translate(vel.dx * dt, vel.dy * dt);
    }
}

/// SIMD-optimized movement system (for large numbers of entities)
pub fn simdMovementSystem(world: *World, dt: f32) !void {
    const pos_type_id = getPositionTypeId();
    const vel_type_id = getVelocityTypeId();
    
    if (world.query_system) |*query_sys| {
        var query_result = try query_sys.queryTwo(pos_type_id, vel_type_id);
        defer query_result.deinit();
        
        // Collect all positions and velocities for SIMD processing
        var positions = std.ArrayList(*Position).init(world.allocator);
        var velocities = std.ArrayList(*Velocity).init(world.allocator);
        defer positions.deinit();
        defer velocities.deinit();
        
        var iter = query_result.iterator();
        while (iter.next()) |entity_id| {
            const pos_component = query_sys.getComponent(entity_id, pos_type_id);
            const vel_component = query_sys.getComponent(entity_id, vel_type_id);
            
            if (pos_component != null and vel_component != null) {
                try positions.append(Position.fromComponent(pos_component.?));
                try velocities.append(Velocity.fromComponent(vel_component.?));
            }
        }
        
        // Process with SIMD (simplified - real SIMD would use vector instructions)
        const count = positions.items.len;
        const simd_width = 4; // Process 4 entities at once
        
        var i: usize = 0;
        while (i + simd_width <= count) {
            // Vectorized update (in practice, this would use actual SIMD instructions)
            for (0..simd_width) |j| {
                const pos = positions.items[i + j];
                const vel = velocities.items[i + j];
                pos.translate(vel.dx * dt, vel.dy * dt);
            }
            i += simd_width;
        }
        
        // Handle remaining entities
        while (i < count) {
            const pos = positions.items[i];
            const vel = velocities.items[i];
            pos.translate(vel.dx * dt, vel.dy * dt);
            i += 1;
        }
    } else {
        return movementSystemFallback(world, dt);
    }
}
