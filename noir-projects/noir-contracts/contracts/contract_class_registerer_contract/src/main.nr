mod events;
mod capsule;

use dep::aztec::macros::aztec;

#[aztec]
contract ContractClassRegisterer {
    use dep::aztec::protocol_types::{
        contract_class_id::ContractClassId,
        constants::{
        ARTIFACT_FUNCTION_TREE_MAX_HEIGHT, FUNCTION_TREE_HEIGHT,
        MAX_PACKED_BYTECODE_SIZE_PER_PRIVATE_FUNCTION_IN_FIELDS,
        MAX_PACKED_BYTECODE_SIZE_PER_UNCONSTRAINED_FUNCTION_IN_FIELDS,
        MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS
    },
        abis::log_hash::LogHash
    };

    use dep::aztec::{
        context::PrivateContext, oracle::logs::emit_contract_class_unencrypted_log_private,
        macros::functions::private
    };

    use crate::events::{
        class_registered::ContractClassRegistered,
        private_function_broadcasted::{ClassPrivateFunctionBroadcasted, PrivateFunction, InnerPrivateFunction},
        unconstrained_function_broadcasted::{ClassUnconstrainedFunctionBroadcasted, UnconstrainedFunction, InnerUnconstrainedFunction}
    };

    // docs:start:import_pop_capsule
    use crate::capsule::pop_capsule;
    // docs:end:import_pop_capsule

    #[private]
    #['private]
    fn register(
        artifact_hash: Field,
        private_functions_root: Field,
        public_bytecode_commitment: Field
    ) {
        // TODO: Validate public_bytecode_commitment is the correct commitment of packed_public_bytecode
        // TODO: Validate packed_public_bytecode is legit public bytecode

        // docs:start:pop_capsule
        let packed_public_bytecode: [Field; MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS] = pop_capsule();
        // docs:end:pop_capsule

        // Compute contract class id from preimage
        let contract_class_id = ContractClassId::compute(
            artifact_hash,
            private_functions_root,
            public_bytecode_commitment
        );

        // Emit the contract class id as a nullifier to be able to prove that this class has been (not) registered
        let event = ContractClassRegistered { contract_class_id, version: 1, artifact_hash, private_functions_root, packed_public_bytecode };
        context.push_nullifier(contract_class_id.to_field());

        // Broadcast class info including public bytecode
        dep::aztec::oracle::debug_log::debug_log_format(
            "ContractClassRegistered: {}",
            [
            contract_class_id.to_field(),
            artifact_hash,
            private_functions_root,
            public_bytecode_commitment
        ]
        );
        emit_contract_class_unencrypted_log(&mut context, event.serialize());
    }

    #[private]
    #['private]
    fn broadcast_private_function(
        contract_class_id: ContractClassId,
        artifact_metadata_hash: Field,
        unconstrained_functions_artifact_tree_root: Field,
        private_function_tree_sibling_path: [Field; FUNCTION_TREE_HEIGHT],
        private_function_tree_leaf_index: Field,
        artifact_function_tree_sibling_path: [Field; ARTIFACT_FUNCTION_TREE_MAX_HEIGHT],
        artifact_function_tree_leaf_index: Field,
        function_data: InnerPrivateFunction
    ) {
        let private_bytecode: [Field; MAX_PACKED_BYTECODE_SIZE_PER_PRIVATE_FUNCTION_IN_FIELDS] = pop_capsule();

        let event = ClassPrivateFunctionBroadcasted {
            contract_class_id,
            artifact_metadata_hash,
            unconstrained_functions_artifact_tree_root,
            private_function_tree_sibling_path,
            private_function_tree_leaf_index,
            artifact_function_tree_sibling_path,
            artifact_function_tree_leaf_index,
            function: PrivateFunction {
                selector: function_data.selector,
                metadata_hash: function_data.metadata_hash,
                vk_hash: function_data.vk_hash,
                bytecode: private_bytecode
            }
        };
        dep::aztec::oracle::debug_log::debug_log_format(
            "ClassPrivateFunctionBroadcasted: {}",
            [
            contract_class_id.to_field(),
            artifact_metadata_hash,
            unconstrained_functions_artifact_tree_root,
            function_data.selector.to_field(),
            function_data.vk_hash,
            function_data.metadata_hash
        ]
        );
        emit_contract_class_unencrypted_log(&mut context, event.serialize());
    }

    #[private]
    #['private]
    fn broadcast_unconstrained_function(
        contract_class_id: ContractClassId,
        artifact_metadata_hash: Field,
        private_functions_artifact_tree_root: Field,
        artifact_function_tree_sibling_path: [Field; ARTIFACT_FUNCTION_TREE_MAX_HEIGHT],
        artifact_function_tree_leaf_index: Field,
        function_data: InnerUnconstrainedFunction
    ) {
        let unconstrained_bytecode: [Field; MAX_PACKED_BYTECODE_SIZE_PER_UNCONSTRAINED_FUNCTION_IN_FIELDS] = pop_capsule();
        let event = ClassUnconstrainedFunctionBroadcasted {
            contract_class_id,
            artifact_metadata_hash,
            private_functions_artifact_tree_root,
            artifact_function_tree_sibling_path,
            artifact_function_tree_leaf_index,
            function: UnconstrainedFunction {
                selector: function_data.selector,
                metadata_hash: function_data.metadata_hash,
                bytecode: unconstrained_bytecode
            }
        };
        dep::aztec::oracle::debug_log::debug_log_format(
            "ClassUnconstrainedFunctionBroadcasted: {}",
            [
            contract_class_id.to_field(),
            artifact_metadata_hash,
            private_functions_artifact_tree_root,
            function_data.selector.to_field(),
            function_data.metadata_hash
        ]
        );
        emit_contract_class_unencrypted_log(&mut context, event.serialize());
    }

    #[contract_library_method]
    fn emit_contract_class_unencrypted_log<let N: u32>(context: &mut PrivateContext, log: [Field; N]) {
        let contract_address = context.this_address();
        let counter = context.next_counter();

        // The log preimage is too large for the hash to compile (16,200 fields, 518,400 bytes), so we do this via a
        // specialized oracle.
        // A malicious oracle cannot force us to use an incorrect bytecode:
        // - Contract class -> we will commit to the packed bytecode (currently a TODO)
        // - Private function -> we provide a membership proof
        // - Unconstrained function -> we provide a membership proof
        // However, the sequencer will be required to know a contract's preimage if it is called and the sequencer
        // cannot prove non-registration. Therefore, it is possible that a malicious oracle might prevent sequencers
        // from including transactions with calls to certain badly-broadcasted contracts.
        // TODO(#8978): review correctness
        let log_hash = emit_contract_class_unencrypted_log_private(contract_address, log, counter);

        // 40 = addr (32) + raw log len (4) + processed log len (4)
        context.unencrypted_logs_hashes.push(LogHash { value: log_hash, counter, length: 40 + (N as Field) * 32 });
    }
}
