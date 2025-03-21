use dep::aztec::macros::aztec;

#[aztec]
contract BoxReact {
    use dep::aztec::{
        protocol_types::public_keys::{IvpkM, OvpkM},
        prelude::{AztecAddress, PrivateMutable, Map, NoteInterface, NoteHeader, Point},
        encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
        macros::{storage::storage, functions::{private, public, initializer}}
    };
    use dep::value_note::value_note::ValueNote;

    #[storage]
    struct Storage<Context> {
        numbers: Map<AztecAddress, PrivateMutable<ValueNote, Context>, Context>,
    }

    #[private]
    #['private]
    #['initializer]
    fn constructor(
        number: Field,
        owner: AztecAddress,
        owner_npk_m_hash: Field,
        owner_ovpk_m: OvpkM,
        owner_ivpk_m: IvpkM
    ) {
        let numbers = storage.numbers;
        let mut new_number = ValueNote::new(number, owner_npk_m_hash);
        numbers.at(owner).initialize(&mut new_number).emit(encode_and_encrypt_note(&mut context, owner_ovpk_m, owner_ivpk_m, owner));
    }

    #[private]
    #['private]
    fn setNumber(
        number: Field,
        owner: AztecAddress,
        owner_npk_m_hash: Field,
        owner_ovpk_m: OvpkM,
        owner_ivpk_m: IvpkM
    ) {
        let numbers = storage.numbers;
        let mut new_number = ValueNote::new(number, owner_npk_m_hash);
        numbers.at(owner).replace(&mut new_number).emit(encode_and_encrypt_note(&mut context, owner_ovpk_m, owner_ivpk_m, owner));
    }

    unconstrained fn getNumber(owner: AztecAddress) -> pub ValueNote {
        let numbers = storage.numbers;
        numbers.at(owner).view_note()
    }
}
