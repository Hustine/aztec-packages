use crate::{
    abis::{
    append_only_tree_snapshot::{AppendOnlyTreeSnapshot, APPEND_ONLY_TREE_SNAPSHOT_LENGTH},
    global_variables::GlobalVariables
},
    constants::{
    GENERATOR_INDEX__BLOCK_HASH, GLOBAL_VARIABLES_LENGTH, HEADER_LENGTH, STATE_REFERENCE_LENGTH,
    CONTENT_COMMITMENT_LENGTH
},
    hash::poseidon2_hash_with_separator, state_reference::StateReference,
    traits::{Deserialize, Empty, Hash, Serialize}, utils::arr_copy_slice,
    content_commitment::ContentCommitment
};

// docs:start:header
pub struct Header {
    last_archive: AppendOnlyTreeSnapshot,
    content_commitment: ContentCommitment,
    state: StateReference,
    global_variables: GlobalVariables,
    total_fees: Field
}
// docs:end:header

impl Eq for Header {
    fn eq(self, other: Self) -> bool {
        self.last_archive.eq(other.last_archive)
            & self.content_commitment.eq(other.content_commitment)
            & self.state.eq(other.state)
            & self.global_variables.eq(other.global_variables)
            & self.total_fees.eq(other.total_fees)
    }
}

impl Serialize<HEADER_LENGTH> for Header {
    fn serialize(self) -> [Field; HEADER_LENGTH] {
        let mut fields: BoundedVec<Field, HEADER_LENGTH> = BoundedVec::new();

        fields.extend_from_array(self.last_archive.serialize());
        fields.extend_from_array(self.content_commitment.serialize());
        fields.extend_from_array(self.state.serialize());
        fields.extend_from_array(self.global_variables.serialize());
        fields.push(self.total_fees);

        fields.storage
    }
}

impl Deserialize<HEADER_LENGTH> for Header {
    fn deserialize(serialized: [Field; HEADER_LENGTH]) -> Self {
        let mut offset = 0;

        let last_archive_fields = arr_copy_slice(serialized, [0; APPEND_ONLY_TREE_SNAPSHOT_LENGTH], offset);
        offset = offset + APPEND_ONLY_TREE_SNAPSHOT_LENGTH;

        let content_commitment_fields = arr_copy_slice(serialized, [0; CONTENT_COMMITMENT_LENGTH], offset);
        offset = offset + CONTENT_COMMITMENT_LENGTH;

        let state_fields = arr_copy_slice(serialized, [0; STATE_REFERENCE_LENGTH], offset);
        offset = offset + STATE_REFERENCE_LENGTH;

        let global_variables_fields = arr_copy_slice(serialized, [0; GLOBAL_VARIABLES_LENGTH], offset);
        offset = offset + GLOBAL_VARIABLES_LENGTH;

        let total_fees = serialized[offset];

        Header {
            last_archive: AppendOnlyTreeSnapshot::deserialize(last_archive_fields),
            content_commitment: ContentCommitment::deserialize(content_commitment_fields),
            state: StateReference::deserialize(state_fields),
            global_variables: GlobalVariables::deserialize(global_variables_fields),
            total_fees
        }
    }
}

impl Empty for Header {
    fn empty() -> Self {
        Self {
            last_archive: AppendOnlyTreeSnapshot::zero(),
            content_commitment: ContentCommitment::empty(),
            state: StateReference::empty(),
            global_variables: GlobalVariables::empty(),
            total_fees: 0
        }
    }
}

impl Hash for Header {
    fn hash(self) -> Field {
        poseidon2_hash_with_separator(self.serialize(), GENERATOR_INDEX__BLOCK_HASH)
    }
}

#[test]
fn serialization_of_empty() {
    let header = Header::empty();
    let serialized = header.serialize();
    let deserialized = Header::deserialize(serialized);
    assert(header.eq(deserialized));
}

#[test]
fn hash_smoke() {
    let header = Header::empty();
    let _hashed = header.hash();
}

#[test]
fn empty_hash_is_zero() {
    let header = Header::empty();
    let hash = header.hash();

    // Value from new_contract_data.test.ts "computes empty hash" test
    let test_data_empty_hash = 0x1c97ed6fbc35f8b400d31bd38ce5cc938921e0cf2e20159d316f8c7011f9f42c;
    assert_eq(hash, test_data_empty_hash);
}
