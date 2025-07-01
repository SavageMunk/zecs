const std = @import("std");
const Allocator = std.mem.Allocator;

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

/// Helper for creating components with automatic type ID generation
pub fn ComponentHelper(comptime T: type) type {
    return struct {
        const ComponentType = T;
        pub const TYPE_ID: u32 = typeId(T);
        
        /// Initialize the component with a vtable
        pub fn init(component_data: T, allocator: Allocator) !*T {
            const self = try allocator.create(T);
            self.* = component_data;
            
            // If the component has a 'component' field, initialize it
            if (@hasField(T, "component")) {
                self.component = Component{
                    .type_id = TYPE_ID,
                    .vtable = &vtable,
                };
            }
            
            return self;
        }
        
        const vtable = Component.VTable{
            .destroy = destroy,
            .clone = clone,
        };
        
        fn destroy(component: *Component, allocator: Allocator) void {
            const self: *T = @fieldParentPtr("component", component);
            allocator.destroy(self);
        }
        
        fn clone(component: *Component, allocator: Allocator) *Component {
            const self: *T = @fieldParentPtr("component", component);
            
            // Create a copy of the component data
            var component_copy = self.*;
            
            // Remove the component field from the copy to avoid duplicating vtable
            if (@hasField(T, "component")) {
                component_copy.component = undefined;
            }
            
            const new_component = ComponentHelper(T).init(component_copy, allocator) catch unreachable;
            return &new_component.component;
        }
        
        pub fn fromComponent(component: *Component) *T {
            return @fieldParentPtr("component", component);
        }
    };
}

/// Generate a unique type ID for a component type
fn typeId(comptime T: type) u32 {
    // Simple hash of the type name for now
    const type_name = @typeName(T);
    var hash: u32 = 0;
    for (type_name) |c| {
        hash = hash *% 31 +% c;
    }
    return hash;
}

test "component type ID generation" {
    const TestComponent = struct {
        component: Component,
        value: i32,
    };
    const Helper = ComponentHelper(TestComponent);
    try std.testing.expect(Helper.TYPE_ID != 0);
}

test "component helper initialization" {
    const TestComponent = struct {
        component: Component,
        value: i32,
    };
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const Helper = ComponentHelper(TestComponent);
    const comp = try Helper.init(.{ .component = undefined, .value = 42 }, allocator);
    defer allocator.destroy(comp);
    
    try std.testing.expectEqual(@as(i32, 42), comp.value);
    try std.testing.expectEqual(Helper.TYPE_ID, comp.component.type_id);
}
