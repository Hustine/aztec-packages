// A contract used along with `StaticParent` contract to test static calls.
use dep::aztec::macros::aztec;

#[aztec]
contract StaticChild {
    use dep::aztec::prelude::{AztecAddress, PublicMutable, PrivateSet};

    use dep::aztec::{
        note::{note_getter_options::NoteGetterOptions},
        encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
        keys::getters::get_public_keys, utils::comparison::Comparator,
        macros::{storage::storage, functions::{private, public, view}}
    };
    use dep::value_note::value_note::ValueNote;

    #[storage]
    struct Storage<Context> {
        current_value: PublicMutable<Field, Context>,
        a_private_value: PrivateSet<ValueNote, Context>,
    }

    // Returns base_value + chain_id + version + block_number + timestamp statically
    #[public]
    #['public]
    #['view]
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

    // View function that attempts to modify state. Should always fail regardless how it's called.
    #[private]
    #['private]
    #['view]
    fn private_illegal_set_value(new_value: Field, owner: AztecAddress) -> Field {
        let msg_sender_keys = get_public_keys(context.msg_sender());
        let owner_keys = get_public_keys(owner);

        let mut note = ValueNote::new(new_value, owner_keys.npk_m.hash());

        storage.a_private_value.insert(&mut note).emit(encode_and_encrypt_note(&mut context, msg_sender_keys.ovpk_m, owner_keys.ivpk_m, owner));
        new_value
    }

    // Modify a note
    #[private]
    #['private]
    fn private_set_value(
        new_value: Field,
        owner: AztecAddress,
        outgoing_viewer: AztecAddress
    ) -> Field {
        let owner_keys = get_public_keys(owner);
        let outgoing_viewer_keys = get_public_keys(outgoing_viewer);

        let mut note = ValueNote::new(new_value, owner_keys.npk_m.hash());
        storage.a_private_value.insert(&mut note).emit(
            encode_and_encrypt_note(
                &mut context,
                outgoing_viewer_keys.ovpk_m,
                owner_keys.ivpk_m,
                owner
            )
        );
        new_value
    }

    // Retrieve note value statically
    #[private]
    #['private]
    #['view]
    fn private_get_value(amount: Field, owner: AztecAddress) -> Field {
        let owner_npk_m_hash = get_public_keys(owner).npk_m.hash();
        let mut options = NoteGetterOptions::new();
        options = options.select(ValueNote::properties().value, Comparator.EQ, amount).select(
            ValueNote::properties().npk_m_hash,
            Comparator.EQ,
            owner_npk_m_hash
        ).set_limit(1);
        let notes = storage.a_private_value.get_notes(options);
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

    // View function that attempts to modify state. Should always fail regardless how it's called.
    #[public]
    #['public]
    #['view]
    fn pub_illegal_inc_value(new_value: Field) -> Field {
        let old_value = storage.current_value.read();
        storage.current_value.write(old_value + new_value);
        context.emit_unencrypted_log(new_value);
        new_value
    }
}
