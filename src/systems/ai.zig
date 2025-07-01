const std = @import("std");
const World = @import("../core/world.zig").World;
const Position = @import("../components/spatial.zig").Position;
const Velocity = @import("../components/spatial.zig").Velocity;
const AI = @import("../components/gameplay.zig").AI;
const AIState = @import("../components/gameplay.zig").AIState;
const getPositionTypeId = @import("../components/spatial.zig").getPositionTypeId;
const getVelocityTypeId = @import("../components/spatial.zig").getVelocityTypeId;
const getAITypeId = @import("../components/gameplay.zig").getAITypeId;

/// Basic AI system that updates AI states and behaviors
pub fn aiSystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const ai_type_id = getAITypeId();
    var entities_with_ai = try world.getEntitiesWithComponent(ai_type_id, allocator);
    defer entities_with_ai.deinit();
    
    for (entities_with_ai.items) |entity_id| {
        const ai_component = world.getComponent(entity_id, ai_type_id);
        if (ai_component) |component| {
            const ai = AI.fromComponent(component);
            
            ai.update(dt);
            
            if (ai.canMakeDecision()) {
                switch (ai.state) {
                    .idle => {
                        // Randomly decide to start wandering
                        if (std.crypto.random.float(f32) < 0.1) { // 10% chance per decision
                            ai.setState(.wandering);
                            ai.setDecisionCooldown(1.0); // Don't change state for 1 second
                        }
                    },
                    .wandering => {
                        // Randomly decide to stop wandering
                        if (std.crypto.random.float(f32) < 0.05) { // 5% chance per decision
                            ai.setState(.idle);
                            ai.setDecisionCooldown(2.0); // Stay idle for 2 seconds
                        }
                    },
                    .chasing => {
                        // Check if target still exists and is in range
                        if (ai.target) |target_id| {
                            if (!world.hasEntity(target_id)) {
                                ai.setState(.idle);
                                ai.setTarget(null);
                            }
                        } else {
                            ai.setState(.idle);
                        }
                    },
                    .fleeing => {
                        // Check if we've fled long enough
                        if (ai.state_timer > 3.0) { // Flee for 3 seconds
                            ai.setState(.idle);
                            ai.setTarget(null);
                        }
                    },
                    .attacking => {
                        // Attack behavior would go here
                        if (ai.state_timer > 1.0) { // Attack for 1 second
                            ai.setState(.idle);
                        }
                    },
                    .dead => {
                        // Dead entities don't make decisions
                    },
                }
                
                ai.setDecisionCooldown(0.5); // Make decisions every 0.5 seconds
            }
        }
    }
}

/// Wandering system that makes entities with wandering AI move randomly
pub fn wanderingSystem(world: *World, dt: f32) !void {
    _ = dt;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const ai_type_id = getAITypeId();
    const pos_type_id = getPositionTypeId();
    const vel_type_id = getVelocityTypeId();
    
    var entities_with_ai = try world.getEntitiesWithComponent(ai_type_id, allocator);
    defer entities_with_ai.deinit();
    
    for (entities_with_ai.items) |entity_id| {
        const ai_component = world.getComponent(entity_id, ai_type_id);
        const vel_component = world.getComponent(entity_id, vel_type_id);
        
        if (ai_component != null and vel_component != null) {
            const ai = AI.fromComponent(ai_component.?);
            const velocity = Velocity.fromComponent(vel_component.?);
            
            if (ai.state == .wandering) {
                // Change direction occasionally
                if (ai.canMakeDecision() and std.crypto.random.float(f32) < 0.3) {
                    const angle = std.crypto.random.float(f32) * 2.0 * std.math.pi;
                    const speed = 20.0 + std.crypto.random.float(f32) * 30.0; // 20-50 units/sec
                    
                    velocity.set(
                        @cos(angle) * speed,
                        @sin(angle) * speed
                    );
                    
                    ai.setDecisionCooldown(1.0 + std.crypto.random.float(f32) * 2.0); // 1-3 seconds
                }
            } else if (ai.state == .idle) {
                // Stop moving when idle
                velocity.set(0, 0);
            } else if (ai.state == .fleeing and ai.target != null) {
                // Flee from target
                const pos_component = world.getComponent(entity_id, pos_type_id);
                const target_pos_component = world.getComponent(ai.target.?, pos_type_id);
                
                if (pos_component != null and target_pos_component != null) {
                    const position = Position.fromComponent(pos_component.?);
                    const target_position = Position.fromComponent(target_pos_component.?);
                    
                    // Calculate direction away from target
                    const dx = position.x - target_position.x;
                    const dy = position.y - target_position.y;
                    const distance = @sqrt(dx * dx + dy * dy);
                    
                    if (distance > 0) {
                        const flee_speed = 80.0;
                        velocity.set(
                            (dx / distance) * flee_speed,
                            (dy / distance) * flee_speed
                        );
                    }
                }
            }
        }
    }
}
