# Ravi runtime value ABI

Ravi's selected runtime slot is the 64-bit NaN-boxed `src/vm/value.zig.Value`.
This contract applies to the interpreter, optimized dispatcher, native ABI,
debugger values, collection keys, and FFI adapters.

## Representation

- Ordinary IEEE-754 values, infinities, and a canonical quiet NaN represent
  floating-point values.
- Tagged quiet-NaN payloads represent `none`, booleans, signed 48-bit integers,
  object pointers, and typed object handles.
- Integers are restricted to `[-2^47, 2^47-1]`. Checked construction reports
  `IntegerOutOfRange`; execution must never silently truncate.
- Object pointers use the low canonical 48 address bits and restore sign
  extension when decoded. Unsupported pointer models must select a portable
  tagged-union build rather than weakening this assumption.
- Typed handles dedicate eight payload bits to `ObjectKind` and forty bits to
  an index. Different object kinds cannot alias even when indexes match.

## Equality and hashing

- Values of different non-numeric tags are unequal. Integer and floating-point
  values use numeric equality at the runtime boundary, so `3` and `3.0`
  compare equal when both are finite and exactly represent the same number.
- Floating equality follows IEEE-754: NaN is unequal to itself and signed zero
  compares equal. Hashing normalizes signed zero so equal values hash equally.
- Integral floating-point values in the representable 48-bit range hash like
  their integer counterpart, preserving the equality/hash contract.
- Object identity is pointer or typed-handle identity until an object's type
  supplies structural equality and hashing.

## Handles and ownership

- Handles contain an object kind and a table index. A handle is valid only while
  its table entry points to a live collector-managed allocation.
- The VM rebuilds precise roots from live stack values, frame locals, captures,
  and the active exception before collection. Table capacity is not a root.
- Swept entries are rejected by live-allocation checks; stale handles produce a
  runtime error instead of dereferencing reclaimed memory.
- The initial collector is non-moving. Future moving collectors must either
  update pointer slots or preserve the public handle contract.

## FFI and collection safety

FFI boundaries pass the raw 64-bit slot together with the ABI version. Foreign
code must use checked constructors and predicates rather than manufacturing
tag bits. Collection hashing must dispatch through `Value.hash` and object
type descriptors. Foreign code must not retain a handle after its owning VM or
collector is destroyed.

## Compatibility policy

`src/vm/value.zig` is the sole runtime value representation. The former
union-based `src/runtime/value.zig` compatibility module has been removed from
the source tree and build graph; new runtime, collection, debugger, and FFI
code must use the NaN-boxed `Value` ABI.
