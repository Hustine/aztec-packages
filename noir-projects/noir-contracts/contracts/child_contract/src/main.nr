// A contract used along with `Parent` contract to test nested calls.
use dep::aztec::macros::aztec;

#[aztec]
contract Child {
    use dep::aztec::prelude::{AztecAddress, PublicMutable, PrivateSet, Map};

    use dep::aztec::{
        note::{note_getter_options::NoteGetterOptions},
        encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
        keys::getters::get_public_keys, utils::comparison::Comparator,
        macros::{storage::storage, functions::{private, public, internal}}
    };
    use dep::value_note::value_note::ValueNote;

    #[storage]
    struct Storage<Context> {
        current_value: PublicMutable<Field, Context>,
        a_map_with_private_values: Map<AztecAddress, PrivateSet<ValueNote, Context>, Context>,
    }

    // Returns a sum of the input and the chain id and version of the contract in private circuit public input's return_values.
    #[private]
    #['private]
    fn value(input: Field) -> Field {
        input + context.chain_id() + context.version()
    }
    // Returns a sum of the input and the chain id and version of the contract in private circuit public input's return_values.
    // Can only be called from this contract.
    #[private]
    #['private]
    #['internal]
    fn value_internal(input: Field) -> Field {
        input + context.chain_id() + context.version()
    }

    // Returns base_value + chain_id + version + block_number + timestamp
    #[public]
    #['public]
    fn pub_get_value(base_value: Field) -> Field {
        let return_value = base_value
            + context.chain_id()
            + context.version()
            + context.block_number()
            + context.timestamp() as Field;

        return_value
    }

    // Sets `current_value` to `new_value`
    #[public]
    #['public]
    fn pub_set_value(new_value: Field) -> Field {
        storage.current_value.write(new_value);
        context.emit_unencrypted_log(new_value);

        new_value
    }

    #[private]
    #['private]
    fn private_set_value(new_value: Field, owner: AztecAddress) -> Field {
        let owner_keys = get_public_keys(owner);

        let mut note = ValueNote::new(new_value, owner_keys.npk_m.hash());
        storage.a_map_with_private_values.at(owner).insert(&mut note).emit(encode_and_encrypt_note(&mut context, owner_keys.ovpk_m, owner_keys.ivpk_m, owner));
        new_value
    }

    #[private]
    #['private]
    fn private_get_value(amount: Field, owner: AztecAddress) -> Field {
        let mut options = NoteGetterOptions::new();
        options = options.select(ValueNote::properties().value, Comparator.EQ, amount).set_limit(1);
        let notes = storage.a_map_with_private_values.at(owner).get_notes(options);
        notes.get(0).value
    }

    // Increments `current_value` by `new_value`
    #[public]
    #['public]
    fn pub_inc_value(new_value: Field) -> Field {
        let old_value = storage.current_value.read();
        storage.current_value.write(old_value + new_value);
        context.emit_unencrypted_log(new_value);

        new_value
    }

    // Increments `current_value` by `new_value`. Can only be called from this contract.
    #[public]
    #['public]
    #['internal]
    fn pub_inc_value_internal(new_value: Field) -> Field {
        let old_value = storage.current_value.read();
        storage.current_value.write(old_value + new_value);
        context.emit_unencrypted_log(new_value);

        new_value
    }

    #[public]
    #['public]
    fn set_value_twice_with_nested_first() {
        let _result = Child::at(context.this_address()).pub_set_value(10).call(&mut context);
        storage.current_value.write(20);
        context.emit_unencrypted_log(20);
    }

    #[public]
    #['public]
    fn set_value_twice_with_nested_last() {
        storage.current_value.write(20);
        context.emit_unencrypted_log(20);
        let _result = Child::at(context.this_address()).pub_set_value(10).call(&mut context);
    }

    #[public]
    #['public]
    fn set_value_with_two_nested_calls() {
        Child::at(context.this_address()).set_value_twice_with_nested_first().call(&mut context);
        Child::at(context.this_address()).set_value_twice_with_nested_last().call(&mut context);
        storage.current_value.write(20);
        context.emit_unencrypted_log(20);
    }
}
