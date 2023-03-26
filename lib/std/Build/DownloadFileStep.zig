const std = @import("../std.zig");
const Step = std.Build.Step;
const Uri = std.Uri;
const FileSource = std.Build.FileSource;
const InstallDir = std.Build.InstallDir;
const DownloadFileStep = @This();
const assert = std.debug.assert;

pub const base_id = .download_file;

step: Step,
uri: Uri,
dir: InstallDir,
dest_rel_path: []const u8,

pub fn create(
    owner: *std.Build,
    uri: []const u8,
    dir: InstallDir,
    dest_rel_path: []const u8,
) *DownloadFileStep {
    assert(dest_rel_path.len != 0);
    owner.pushInstalledFile(dir, dest_rel_path);
    const self = owner.allocator.create(DownloadFileStep) catch @panic("OOM");
    self.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("download {s} to {s}", .{ uri, dest_rel_path }),
            .owner = owner,
            .makeFn = make,
        }),
        .uri = Uri.parse(uri) catch unreachable,
        .dir = dir.dupe(owner),
        .dest_rel_path = owner.dupePath(dest_rel_path),
    };
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    const b = step.owner;
    const self = @fieldParentPtr(DownloadFileStep, "step", step);

    const file_path = b.getInstallPath(self.dir, self.dest_rel_path);
    if (b.build_root.handle.access(file_path, .{})) {
        step.result_cached = true;
        return;
    } else |_| {}

    var client = std.http.Client{ .allocator = b.allocator };
    defer client.deinit();

    var req = client.request(self.uri, .{}, .{}) catch |err| {
        return step.fail("unable to download from '{}' to '{s}': {s}", .{
            self.uri, file_path, @errorName(err),
        });
    };
    defer req.deinit();

    const data = try req.reader().readAllAlloc(b.allocator, std.math.maxInt(usize));
    if (std.fs.path.dirname(file_path)) |dirname| {
        b.build_root.handle.makePath(dirname) catch |err| {
            return step.fail("unable to make path '{}{s}': {s}", .{
                b.build_root, dirname, @errorName(err),
            });
        };
    }

    try b.build_root.handle.writeFile(file_path, data);
}
