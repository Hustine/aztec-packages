use dep::protocol_types::{constants::PUBLIC_DATA_TREE_HEIGHT, data::PublicDataTreeLeafPreimage, utils::arr_copy_slice};

global LEAF_PREIMAGE_LENGTH: u32 = 4;
global PUBLIC_DATA_WITNESS: u32 = 45;

pub struct PublicDataWitness {
    index: Field,
    leaf_preimage: PublicDataTreeLeafPreimage,
    path: [Field; PUBLIC_DATA_TREE_HEIGHT],
}

#[oracle(getPublicDataTreeWitness)]
unconstrained fn get_public_data_witness_oracle(
    _block_number: u32,
    _public_data_tree_index: Field
) -> [Field; PUBLIC_DATA_WITNESS] {}

pub unconstrained fn get_public_data_witness(
    block_number: u32,
    public_data_tree_index: Field
) -> PublicDataWitness {
    let fields = get_public_data_witness_oracle(block_number, public_data_tree_index);
    PublicDataWitness {
        index: fields[0],
        leaf_preimage: PublicDataTreeLeafPreimage { slot: fields[1], value: fields[2], next_index: fields[3] as u32, next_slot: fields[4] },
        path: arr_copy_slice(fields, [0; PUBLIC_DATA_TREE_HEIGHT], 1 + LEAF_PREIMAGE_LENGTH)
    }
}
