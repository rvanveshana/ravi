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

- Values of different tags are unequal. Ravi does not implicitly equate an
  integer slot with a floating-point slot at this ABI layer; language-level
  numeric conversion is explicit in HIR.
- Floating equality follows IEEE-754: NaN is unequal to itself and signed zero
  compares equal. Hashing normalizes signed zero so equal values hash equally.
- Object identity is pointer or typed-handle identity until an object's type
  supplies structural equality and hashing.

## FFI and collection safety

FFI boundaries pass the raw 64-bit slot together with the ABI version. Foreign
code must use checked constructors and predicates rather than manufacturing
tag bits. Collection hashing must dispatch through `Value.hash` and object
type descriptors. GC-moving implementations must update pointer slots or use
stable handles; the initial collector is non-moving.
