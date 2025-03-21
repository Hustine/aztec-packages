use dep::aztec::prelude::{NullifiableNote, PrivateContext, NoteHeader};
use dep::aztec::{
    note::{utils::compute_note_hash_for_nullify}, keys::getters::get_nsk_app,
    protocol_types::{traits::Serialize, constants::GENERATOR_INDEX__NOTE_NULLIFIER, hash::poseidon2_hash_with_separator},
    macros::notes::note
};

// docs:start:state_vars-CardNote
global CARD_NOTE_LEN: u32 = 3; // 3 plus a header.

#[note]
pub struct CardNote {
    points: u8,
    randomness: Field,
    // The nullifying public key hash is used with the nsk_app to ensure that the note can be privately spent.
    npk_m_hash: Field,
}
// docs:end:state_vars-CardNote

// docs:start:cardnote_impl
impl CardNote {
    pub fn new(points: u8, randomness: Field, npk_m_hash: Field) -> Self {
        CardNote { points, randomness, npk_m_hash, header: NoteHeader::empty() }
    }
}
// docs:end:cardnote_impl

// docs:start:note_interface
impl NullifiableNote for CardNote {
    fn compute_nullifier(self, context: &mut PrivateContext, note_hash_for_nullify: Field) -> Field {
        let secret = context.request_nsk_app(self.npk_m_hash);
        poseidon2_hash_with_separator(
            [
            note_hash_for_nullify,
            secret
        ],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field
        )
    }

    unconstrained fn compute_nullifier_without_context(self) -> Field {
        let note_hash_for_nullify = compute_note_hash_for_nullify(self);
        let secret = get_nsk_app(self.npk_m_hash);
        poseidon2_hash_with_separator(
            [
            note_hash_for_nullify,
            secret
        ],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field
        )
    }
}
// docs:end:note_interface

// docs:start:serialize
impl Serialize<3> for CardNote {
    fn serialize(self) -> [Field; 3] {
        [self.points.to_field(), self.randomness, self.npk_m_hash.to_field()]
    }
}
// docs:end:serialize

impl Eq for CardNote {
    fn eq(self, other: Self) -> bool {
        (self.points == other.points)
            & (self.npk_m_hash == other.npk_m_hash)
            & (self.randomness == other.randomness)
    }
}
