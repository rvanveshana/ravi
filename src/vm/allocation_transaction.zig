pub const Snapshot = struct {
    arrays: usize,
    dicts: usize,
    closures: usize,
    cells: usize,
    instances: usize,
    exceptions: usize,
    strings: usize,
    roots: usize,
    channels: usize,
    pub fn begin(vm: anytype) Snapshot {
        return .{ .arrays = vm.array_count, .dicts = vm.dict_count, .closures = vm.closure_count, .cells = vm.cell_count, .instances = vm.instance_count, .exceptions = vm.exception_count, .strings = vm.strings.items.len, .roots = vm.gc_roots.items.len, .channels = vm.channels.items.len };
    }
    pub fn rollback(self: Snapshot, vm: anytype) void {
        for (vm.gc_roots.items[self.roots..]) |root| {
            vm.collector.removeRoot(root);
            vm.collector.discardUnpublished(root);
        }
        vm.gc_roots.items.len = self.roots;
        vm.array_count = self.arrays;
        vm.dict_count = self.dicts;
        vm.closure_count = self.closures;
        vm.cell_count = self.cells;
        vm.instance_count = self.instances;
        vm.exception_count = self.exceptions;
        vm.strings.items.len = self.strings;
        for (vm.channels.items[self.channels..]) |channel| channel.release();
        vm.channels.items.len = self.channels;
    }
};
