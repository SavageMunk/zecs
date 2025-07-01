const std = @import("std");
const Allocator = std.mem.Allocator;
const EntityId = u64; // Or import your actual EntityId type

/// TimeSkipComponent: Attach to entities for event-based/background simulation
pub const TimeSkipComponent = struct {
    last_update_time: i64, // Unix timestamp or tick count
    // Add more fields as needed (e.g., accumulated work, AI state, etc.)

    pub fn init(now: i64) TimeSkipComponent {
        return TimeSkipComponent{
            .last_update_time = now,
        };
    }

    /// Simulate this entity for the elapsed time (in seconds or ticks)
    pub fn simulateFor(self: *TimeSkipComponent, elapsed: i64) void {
        _ = self;
        _ = elapsed;
        // Example: accumulate resources, run AI, etc.
        // Replace this with your actual simulation logic
        // std.debug.print("Simulating entity for {d} seconds\n", .{elapsed});
    }
};

/// Example ECS integration helper
pub fn timeSkipUpdate(
    entities: []EntityId,
    time_components: []TimeSkipComponent,
    now: i64,
    isActive: fn (EntityId) bool,
) void {
    for (entities, time_components) |entity_id, *tsc| {
        if (isActive(entity_id)) {
            // Real-time update: set last_update_time to now
            tsc.last_update_time = now;
        } else {
            // Off-screen: catch up
            const elapsed = now - tsc.last_update_time;
            if (elapsed > 0) {
                tsc.simulateFor(elapsed);
                tsc.last_update_time = now;
            }
        }
    }
}
