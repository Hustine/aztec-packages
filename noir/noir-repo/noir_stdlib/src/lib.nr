pub mod hash;
pub mod aes128;
pub mod array;
pub mod slice;
pub mod merkle;
pub mod schnorr;
pub mod ecdsa_secp256k1;
pub mod ecdsa_secp256r1;
pub mod eddsa;
pub mod embedded_curve_ops;
pub mod sha256;
pub mod sha512;
pub mod field;
pub mod ec;
pub mod collections;
pub mod compat;
pub mod convert;
pub mod option;
pub mod string;
pub mod test;
pub mod cmp;
pub mod ops;
pub mod default;
pub mod prelude;
pub mod uint128;
pub mod bigint;
pub mod runtime;
pub mod meta;
pub mod append;
pub mod mem;
pub mod panic;

// Oracle calls are required to be wrapped in an unconstrained function
// Thus, the only argument to the `println` oracle is expected to always be an ident
#[oracle(print)]
unconstrained fn print_oracle<T>(with_newline: bool, input: T) {}

unconstrained fn print_unconstrained<T>(with_newline: bool, input: T) {
    print_oracle(with_newline, input);
}

pub fn println<T>(input: T) {
    unsafe {
        print_unconstrained(true, input);
    }
}

pub fn print<T>(input: T) {
    unsafe {
        print_unconstrained(false, input);
    }
}

pub fn verify_proof<let N: u32, let M: u32, let K: u32>(
    verification_key: [Field; N],
    proof: [Field; M],
    public_inputs: [Field; K],
    key_hash: Field
) {
    verify_proof_internal(verification_key, proof, public_inputs, key_hash, 0);
}

pub fn verify_proof_with_type<let N: u32, let M: u32, let K: u32>(
    verification_key: [Field; N],
    proof: [Field; M],
    public_inputs: [Field; K],
    key_hash: Field,
    proof_type: u32
) {
    if !crate::runtime::is_unconstrained() {
        crate::assert_constant(proof_type);
    }
    verify_proof_internal(verification_key, proof, public_inputs, key_hash, proof_type);
}

#[foreign(recursive_aggregation)]
fn verify_proof_internal<let N: u32, let M: u32, let K: u32>(
    verification_key: [Field; N],
    proof: [Field; M],
    public_inputs: [Field; K],
    key_hash: Field,
    proof_type: u32
) {}

// Asserts that the given value is known at compile-time.
// Useful for debugging for-loop bounds.
#[builtin(assert_constant)]
pub fn assert_constant<T>(x: T) {}

// Asserts that the given value is both true and known at compile-time
#[builtin(static_assert)]
pub fn static_assert<let N: u32>(predicate: bool, message: str<N>) {}

// from_field and as_field are private since they are not valid for every type.
// `as` should be the default for users to cast between primitive types, and in the future
// traits can be used to work with generic types.
#[builtin(from_field)]
fn from_field<T>(x: Field) -> T {}

#[builtin(as_field)]
fn as_field<T>(x: T) -> Field {}

pub fn wrapping_add<T>(x: T, y: T) -> T {
    crate::from_field(crate::as_field(x) + crate::as_field(y))
}

pub fn wrapping_sub<T>(x: T, y: T) -> T {
    //340282366920938463463374607431768211456 is 2^128, it is used to avoid underflow
    crate::from_field(crate::as_field(x) + 340282366920938463463374607431768211456 - crate::as_field(y))
}

pub fn wrapping_mul<T>(x: T, y: T) -> T {
    crate::from_field(crate::as_field(x) * crate::as_field(y))
}

#[builtin(as_witness)]
pub fn as_witness(x: Field) {}

