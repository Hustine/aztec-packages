use dep::aztec::prelude::{PrivateContext, AztecAddress};
use dep::aztec::protocol_types::{
    constants::GENERATOR_INDEX__SIGNATURE_PAYLOAD, hash::poseidon2_hash_with_separator,
    traits::{Hash, Serialize}
};

use dep::authwit::entrypoint::function_call::FunctionCall;

global DAPP_MAX_CALLS: u32 = 1;
// FUNCTION_CALL_SIZE * DAPP_MAX_CALLS + 1
global DAPP_PAYLOAD_SIZE: u32 = 6;
// FUNCTION_CALL_SIZE_IN_BYTES * DAPP_MAX_CALLS + 32
global DAPP_PAYLOAD_SIZE_IN_BYTES: u32 = 130;

// Note: If you change the following struct you have to update default_entrypoint.ts
// docs:start:app-payload-struct
pub struct DAppPayload {
  function_calls: [FunctionCall; DAPP_MAX_CALLS],
  nonce: Field,
}
// docs:end:app-payload-struct

impl Serialize<DAPP_PAYLOAD_SIZE> for DAppPayload {
    // Serializes the entrypoint struct
    fn serialize(self) -> [Field; DAPP_PAYLOAD_SIZE] {
        let mut fields: BoundedVec<Field, DAPP_PAYLOAD_SIZE> = BoundedVec::new();
        for call in self.function_calls {
            fields.extend_from_array(call.serialize());
        }
        fields.push(self.nonce);
        fields.storage
    }
}

impl Hash for DAppPayload {
    fn hash(self) -> Field {
        poseidon2_hash_with_separator(self.serialize(), GENERATOR_INDEX__SIGNATURE_PAYLOAD)
    }
}

impl DAppPayload {
    // Serializes the payload as an array of bytes. Useful for hashing with sha256.
    fn to_be_bytes(self) -> [u8; DAPP_PAYLOAD_SIZE_IN_BYTES] {
        let mut bytes: BoundedVec<u8, DAPP_PAYLOAD_SIZE_IN_BYTES> = BoundedVec::new();

        for i in 0..DAPP_MAX_CALLS {
            bytes.extend_from_array(self.function_calls[i].to_be_bytes());
        }
        bytes.extend_from_array(self.nonce.to_be_bytes::<32>());

        bytes.storage
    }

    // Executes all private and public calls
    // docs:start:entrypoint-execute-calls
    fn execute_calls(self, context: &mut PrivateContext, target_address: AztecAddress) {
        for i in 0..DAPP_MAX_CALLS {
            let call = self.function_calls[i];
            // whitelist the calls that the user can do only go to the expected Dapp contract
            assert(call.target_address == target_address);
            if call.is_public {
                context.call_public_function_with_packed_args(
                    call.target_address,
                    call.function_selector,
                    call.args_hash,
                    call.is_static,
                    false
                );
            } else {
                let _result = context.call_private_function_with_packed_args(
                    call.target_address,
                    call.function_selector,
                    call.args_hash,
                    call.is_static,
                    false
                );
            }
        }
    }
    // docs:end:entrypoint-execute-calls
}
