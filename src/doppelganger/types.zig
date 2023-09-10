pub const Int = i32;
pub const Id = u64;
pub const String = []const u8;

pub const NuclearFlags = packed struct {
    const Flag = u1;

    pub const enabled: Flag = 1;
    pub const disabled: Flag = 0;

    forceNoop: Flag,

    pub fn empty() NuclearFlags {
        return .{
            .forceNoop = NuclearFlags.enabled,
        };
    }
};
