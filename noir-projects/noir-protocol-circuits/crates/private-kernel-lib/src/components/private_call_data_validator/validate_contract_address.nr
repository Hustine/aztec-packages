use dep::types::{
    abis::private_kernel::private_call_data::PrivateCallData, address::AztecAddress,
    constants::MAX_PROTOCOL_CONTRACTS, hash::stdlib_recursion_verification_key_compress_native_vk,
    merkle_tree::root::root_from_sibling_path
};

pub fn validate_contract_address(private_call_data: PrivateCallData, protocol_contract_tree_root: Field) {
    let contract_address = private_call_data.call_stack_item.contract_address;
    assert(!contract_address.is_zero(), "contract address cannot be zero");

    // TODO(https://github.com/AztecProtocol/aztec-packages/issues/3062): Why is this using a hash function from the stdlib::recursion namespace
    let private_call_vk_hash = stdlib_recursion_verification_key_compress_native_vk(private_call_data.vk);

    let computed_address = AztecAddress::compute_from_private_function(
        private_call_data.call_stack_item.function_data.selector,
        private_call_vk_hash,
        private_call_data.function_leaf_membership_witness,
        private_call_data.contract_class_artifact_hash,
        private_call_data.contract_class_public_bytecode_commitment,
        private_call_data.salted_initialization_hash,
        private_call_data.public_keys_hash
    );

    let protocol_contract_index = contract_address.to_field();
    let computed_protocol_contract_tree_root = if (MAX_PROTOCOL_CONTRACTS as Field).lt(protocol_contract_index) {
        0
    } else {
        root_from_sibling_path(
            computed_address.to_field(),
            protocol_contract_index,
            private_call_data.protocol_contract_sibling_path
        )
    };

    assert(
        computed_address.eq(contract_address)
        | computed_protocol_contract_tree_root.eq(protocol_contract_tree_root), "computed contract address does not match expected one"
    );
}
