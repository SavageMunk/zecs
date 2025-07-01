const std = @import("std");
const World = @import("../core/world.zig").World;
const Health = @import("../components/gameplay.zig").Health;
const Energy = @import("../components/gameplay.zig").Energy;
const Lifetime = @import("../components/gameplay.zig").Lifetime;
const Timer = @import("../components/gameplay.zig").Timer;
const getHealthTypeId = @import("../components/gameplay.zig").getHealthTypeId;
const getEnergyTypeId = @import("../components/gameplay.zig").getEnergyTypeId;
const getLifetimeTypeId = @import("../components/gameplay.zig").getLifetimeTypeId;
const getTimerTypeId = @import("../components/gameplay.zig").getTimerTypeId;

/// System that handles health regeneration and death
pub fn healthSystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const health_type_id = getHealthTypeId();
    var entities_with_health = try world.getEntitiesWithComponent(health_type_id, allocator);
    defer entities_with_health.deinit();
    
    var entities_to_destroy = std.ArrayList(@import("../core/entity.zig").EntityId).init(allocator);
    defer entities_to_destroy.deinit();
    
    for (entities_with_health.items) |entity_id| {
        const health_component = world.getComponent(entity_id, health_type_id);
        if (health_component) |component| {
            const health = Health.fromComponent(component);
            
            // Apply regeneration
            health.regenerate(dt);
            
            // Mark dead entities for removal
            if (health.isDead()) {
                try entities_to_destroy.append(entity_id);
            }
        }
    }
    
    // Remove dead entities
    for (entities_to_destroy.items) |entity_id| {
        world.destroyEntity(entity_id);
    }
}

/// System that handles energy regeneration
pub fn energySystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const energy_type_id = getEnergyTypeId();
    var entities_with_energy = try world.getEntitiesWithComponent(energy_type_id, allocator);
    defer entities_with_energy.deinit();
    
    for (entities_with_energy.items) |entity_id| {
        const energy_component = world.getComponent(entity_id, energy_type_id);
        if (energy_component) |component| {
            const energy = Energy.fromComponent(component);
            energy.regenerate(dt);
        }
    }
}

/// System that handles entity lifetime and removal
pub fn lifetimeSystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const lifetime_type_id = getLifetimeTypeId();
    var entities_with_lifetime = try world.getEntitiesWithComponent(lifetime_type_id, allocator);
    defer entities_with_lifetime.deinit();
    
    var entities_to_destroy = std.ArrayList(@import("../core/entity.zig").EntityId).init(allocator);
    defer entities_to_destroy.deinit();
    
    for (entities_with_lifetime.items) |entity_id| {
        const lifetime_component = world.getComponent(entity_id, lifetime_type_id);
        if (lifetime_component) |component| {
            const lifetime = Lifetime.fromComponent(component);
            
            lifetime.update(dt);
            
            if (lifetime.isExpired()) {
                try entities_to_destroy.append(entity_id);
            }
        }
    }
    
    // Remove expired entities
    for (entities_to_destroy.items) |entity_id| {
        world.destroyEntity(entity_id);
    }
}

/// System that handles timers and triggers events
pub fn timerSystem(world: *World, dt: f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const timer_type_id = getTimerTypeId();
    var entities_with_timer = try world.getEntitiesWithComponent(timer_type_id, allocator);
    defer entities_with_timer.deinit();
    
    for (entities_with_timer.items) |entity_id| {
        const timer_component = world.getComponent(entity_id, timer_type_id);
        if (timer_component) |component| {
            const timer = Timer.fromComponent(component);
            
            const triggered = timer.update(dt);
            if (triggered) {
                // Timer triggered - could emit an event here
                // For now, just print debug info
                std.debug.print("Timer triggered for entity {d}\n", .{entity_id});
            }
        }
    }
}
