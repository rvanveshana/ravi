# Runtime value ABI

This is an internal implementation reference. It is not a stable public FFI or
native-library contract. See [Architecture](architecture.md) for integration limits.

## Representation

`src/vm/value.zig` defines the shared 64-bit NaN-boxed `Value` representation.
Ordinary floating-point values and tagged payloads distinguish numbers, booleans,
`none`, pointers, and typed handles.

| Value | Current representation |
| --- | --- |
| Float | IEEE-754 binary64; NaNs canonicalized by construction |
| Integer | Signed 48-bit payload, from `-2^47` through `2^47 - 1` |
| Boolean and none | Dedicated tags |
| Object handle | Eight-bit object kind and forty-bit table index |
| Raw pointer | Encoded using low canonical address bits; portability constrained |

Checked constructors reject unrepresentable integers/handles. A portable alternate
representation is not currently implemented. Do not assume all pointer models or
native targets are supported because the host compiler is Zig.

## Equality and hashing

`Value.eql` and `Value.hash` define primitive numeric/tag behavior. Numeric integer
and float values can compare equal, signed zero is normalized for hashing, and
NaN does not compare equal to itself. Heap-object equality may involve VM operations
beyond raw handle equality. Full structural hashing and user-defined equality
protocols are unfinished.

## Ownership

Handles are local to their owning VM tables and valid only while the referenced
allocation is live. Table capacity is not proof of liveness. Worker arguments and
results reject object handles until a transfer protocol exists; copying the raw
64-bit value does not transfer the object.

The non-moving collector tracks managed allocations, roots, and destructors. VM
root discovery covers active stacks, frame locals/captures, and exceptions, with
further lifetime auditing required for the completed runtime. Constructors roll
back initialized, unpublished objects on failure. Temporary roots and fallible
publication are part of the ownership contract.

Do not expose raw handles or pointers as an application API. A future FFI must
specify versioning, checked construction, root retention, borrowing/transfer,
errors, and suspension explicitly.
