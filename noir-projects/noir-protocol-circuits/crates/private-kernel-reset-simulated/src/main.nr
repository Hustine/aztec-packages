use dep::private_kernel_lib::private_kernel_reset::{PrivateKernelResetHints, PrivateKernelResetCircuitPrivateInputs};
use dep::types::{
    PrivateKernelCircuitPublicInputs,
    constants::{
    MAX_ENCRYPTED_LOGS_PER_TX, MAX_NOTE_HASH_READ_REQUESTS_PER_TX, MAX_NOTE_HASHES_PER_TX,
    MAX_NULLIFIER_READ_REQUESTS_PER_TX, MAX_NULLIFIERS_PER_TX, MAX_KEY_VALIDATION_REQUESTS_PER_TX
}
};
use types::abis::private_kernel_data::PrivateKernelDataWithoutPublicInputs;

global NOTE_HASH_PENDING_AMOUNT = MAX_NOTE_HASH_READ_REQUESTS_PER_TX; // 64
global NOTE_HASH_SETTLED_AMOUNT = MAX_NOTE_HASH_READ_REQUESTS_PER_TX;
global NULLIFIER_PENDING_AMOUNT = MAX_NULLIFIER_READ_REQUESTS_PER_TX; // 64
global NULLIFIER_SETTLED_AMOUNT = MAX_NULLIFIER_READ_REQUESTS_PER_TX;
global NULLIFIER_KEYS = MAX_KEY_VALIDATION_REQUESTS_PER_TX; // 64
global TRANSIENT_DATA_AMOUNT = MAX_NULLIFIERS_PER_TX; // 64
global NOTE_HASH_SILOING_AMOUNT = MAX_NOTE_HASHES_PER_TX; // 64
global NULLIFIER_SILOING_AMOUNT = MAX_NULLIFIERS_PER_TX; // 64
global ENCRYPTED_LOG_SILOING_AMOUNT = MAX_ENCRYPTED_LOGS_PER_TX; // 8

unconstrained fn main(
    previous_kernel: PrivateKernelDataWithoutPublicInputs,
    previous_kernel_public_inputs: PrivateKernelCircuitPublicInputs,
    hints: PrivateKernelResetHints<NOTE_HASH_PENDING_AMOUNT, NOTE_HASH_SETTLED_AMOUNT, NULLIFIER_PENDING_AMOUNT, NULLIFIER_SETTLED_AMOUNT, NULLIFIER_KEYS, TRANSIENT_DATA_AMOUNT>
) -> pub PrivateKernelCircuitPublicInputs {
    let private_inputs = PrivateKernelResetCircuitPrivateInputs::new(previous_kernel, previous_kernel_public_inputs, hints);
    private_inputs.execute(
        NOTE_HASH_SILOING_AMOUNT,
        NULLIFIER_SILOING_AMOUNT,
        ENCRYPTED_LOG_SILOING_AMOUNT
    )
}

