const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Component = @import("../core/component.zig").Component;
const ComponentHelper = @import("../core/component.zig").ComponentHelper;
const EntityId = @import("../core/entity.zig").EntityId;

/// Tag component for labeling entities
pub const Tag = struct {
    const Self = @This();
    
    component: Component,
    name: []const u8,
    
    pub fn init(name: []const u8, allocator: Allocator) !*Self {
        // Make a copy of the name string
        const owned_name = try allocator.dupe(u8, name);
        
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .name = owned_name,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.name);
    }
    
    pub fn matches(self: *Self, tag_name: []const u8) bool {
        return std.mem.eql(u8, self.name, tag_name);
    }
};

/// Parent-child relationship component (parent side)
pub const Parent = struct {
    const Self = @This();
    
    component: Component,
    entity: EntityId,
    
    pub fn init(parent_entity: EntityId, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .entity = parent_entity,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn setParent(self: *Self, parent_entity: EntityId) void {
        self.entity = parent_entity;
    }
    
    pub fn getParent(self: *Self) EntityId {
        return self.entity;
    }
};

/// Parent-child relationship component (children side)
pub const Children = struct {
    const Self = @This();
    
    component: Component,
    entities: ArrayList(EntityId),
    
    pub fn init(allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .entities = ArrayList(EntityId).init(allocator),
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn deinit(self: *Self) void {
        self.entities.deinit();
    }
    
    pub fn addChild(self: *Self, child_entity: EntityId) !void {
        // Check if child already exists
        for (self.entities.items) |entity| {
            if (entity == child_entity) return; // Already a child
        }
        try self.entities.append(child_entity);
    }
    
    pub fn removeChild(self: *Self, child_entity: EntityId) bool {
        for (self.entities.items, 0..) |entity, i| {
            if (entity == child_entity) {
                _ = self.entities.swapRemove(i);
                return true;
            }
        }
        return false;
    }
    
    pub fn hasChild(self: *Self, child_entity: EntityId) bool {
        for (self.entities.items) |entity| {
            if (entity == child_entity) return true;
        }
        return false;
    }
    
    pub fn getChildCount(self: *Self) usize {
        return self.entities.items.len;
    }
    
    pub fn getChildren(self: *Self) []const EntityId {
        return self.entities.items;
    }
    
    pub fn clearChildren(self: *Self) void {
        self.entities.clearRetainingCapacity();
    }
};

/// Group membership component
pub const Group = struct {
    const Self = @This();
    
    component: Component,
    id: u32,
    name: []const u8,
    
    pub fn init(group_id: u32, group_name: []const u8, allocator: Allocator) !*Self {
        const owned_name = try allocator.dupe(u8, group_name);
        
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .id = group_id,
            .name = owned_name,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.name);
    }
    
    pub fn belongsToGroup(self: *Self, group_id: u32) bool {
        return self.id == group_id;
    }
    
    pub fn belongsToGroupByName(self: *Self, group_name: []const u8) bool {
        return std.mem.eql(u8, self.name, group_name);
    }
};

// Helper functions to get component type IDs
pub fn getTagTypeId() u32 {
    return ComponentHelper(Tag).TYPE_ID;
}

pub fn getParentTypeId() u32 {
    return ComponentHelper(Parent).TYPE_ID;
}

pub fn getChildrenTypeId() u32 {
    return ComponentHelper(Children).TYPE_ID;
}

pub fn getGroupTypeId() u32 {
    return ComponentHelper(Group).TYPE_ID;
}

test "tag component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const tag = try Tag.init("player", allocator);
    defer {
        tag.deinit(allocator);
        allocator.destroy(tag);
    }
    
    try std.testing.expect(tag.matches("player"));
    try std.testing.expect(!tag.matches("enemy"));
}

test "children component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const children = try Children.init(allocator);
    defer {
        children.deinit();
        allocator.destroy(children);
    }
    
    try std.testing.expectEqual(@as(usize, 0), children.getChildCount());
    
    try children.addChild(1);
    try children.addChild(2);
    try children.addChild(3);
    
    try std.testing.expectEqual(@as(usize, 3), children.getChildCount());
    try std.testing.expect(children.hasChild(2));
    try std.testing.expect(!children.hasChild(4));
    
    try std.testing.expect(children.removeChild(2));
    try std.testing.expectEqual(@as(usize, 2), children.getChildCount());
    try std.testing.expect(!children.hasChild(2));
}
