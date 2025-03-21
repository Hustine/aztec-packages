mod types;
mod test;

use dep::aztec::macros::aztec;

// Minimal NFT implementation with `AuthWit` support that allows minting in public-only and transfers in both public
// and private.
#[aztec]
contract NFT {
    use dep::compressed_string::FieldCompressedString;
    use dep::aztec::{
        oracle::random::random,
        prelude::{NoteGetterOptions, NoteViewerOptions, Map, PublicMutable, SharedImmutable, PrivateSet, AztecAddress},
        encrypted_logs::{encrypted_note_emission::{encode_and_encrypt_note, encrypt_and_emit_partial_log}},
        hash::pedersen_hash, keys::getters::get_public_keys, note::constants::MAX_NOTES_PER_PAGE,
        protocol_types::traits::is_empty, utils::comparison::Comparator,
        protocol_types::{point::Point, traits::Serialize},
        macros::{storage::storage, events::event, functions::{private, public, view, internal, initializer}}
    };
    use dep::authwit::auth::{assert_current_call_valid_authwit, assert_current_call_valid_authwit_public, compute_authwit_nullifier};
    use std::{embedded_curve_ops::EmbeddedCurvePoint, meta::derive};
    use crate::types::nft_note::NFTNote;

    global TRANSIENT_STORAGE_SLOT_PEDERSEN_INDEX = 3;

    // TODO(#8467): Rename this to Transfer - calling this NFTTransfer to avoid export conflict with the Transfer event
    // in the Token contract.
    #[event]
    #[derive(Serialize)]
    struct NFTTransfer {
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
    }

    #[storage]
    struct Storage<Context> {
        // The symbol of the NFT
        symbol: SharedImmutable<FieldCompressedString, Context>,
        // The name of the NFT
        name: SharedImmutable<FieldCompressedString, Context>,
        // The admin of the contract
        admin: PublicMutable<AztecAddress, Context>,
        // Addresses that can mint
        minters: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
        // Contains the NFTs owned by each address in private.
        private_nfts: Map<AztecAddress, PrivateSet<NFTNote, Context>, Context>,
        // A map from token ID to a boolean indicating if the NFT exists.
        nft_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        // A map from token ID to the public owner of the NFT.
        public_owners: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
    }

    #[public]
    #['public]
    #['initializer]
    fn constructor(admin: AztecAddress, name: str<31>, symbol: str<31>) {
        assert(!admin.is_zero(), "invalid admin");
        storage.admin.write(admin);
        storage.minters.at(admin).write(true);
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
    }

    #[public]
    #['public]
    fn set_admin(new_admin: AztecAddress) {
        assert(storage.admin.read().eq(context.msg_sender()), "caller is not an admin");
        storage.admin.write(new_admin);
    }

    #[public]
    #['public]
    fn set_minter(minter: AztecAddress, approve: bool) {
        assert(storage.admin.read().eq(context.msg_sender()), "caller is not an admin");
        storage.minters.at(minter).write(approve);
    }

    #[public]
    #['public]
    fn mint(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        assert(storage.minters.at(context.msg_sender()).read(), "caller is not a minter");
        assert(storage.nft_exists.at(token_id).read() == false, "token already exists");

        storage.nft_exists.at(token_id).write(true);

        storage.public_owners.at(token_id).write(to);
    }

    #[public]
    #['public]
    #['view]
    fn public_get_name() -> pub FieldCompressedString {
        storage.name.read_public()
    }

    #[private]
    #['private]
    #['view]
    fn private_get_name() -> pub FieldCompressedString {
        storage.name.read_private()
    }

    #[public]
    #['public]
    #['view]
    fn public_get_symbol() -> pub FieldCompressedString {
        storage.symbol.read_public()
    }

    #[private]
    #['private]
    #['view]
    fn private_get_symbol() -> pub FieldCompressedString {
        storage.symbol.read_private()
    }

    #[public]
    #['public]
    #['view]
    fn get_admin() -> Field {
        storage.admin.read().to_field()
    }

    #[public]
    #['public]
    #['view]
    fn is_minter(minter: AztecAddress) -> bool {
        storage.minters.at(minter).read()
    }

    #[public]
    #['public]
    fn transfer_in_public(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }

        let public_owners_storage = storage.public_owners.at(token_id);
        assert(public_owners_storage.read().eq(from), "invalid owner");

        public_owners_storage.write(to);
    }

    /// Prepares a transfer from public balance of `from` to a private balance of `to`. The transfer then needs to be
    /// finalized by calling `finalize_transfer_to_private`. `transient_storage_slot_randomness` is passed
    /// as an argument so that we can derive `transfer_preparer_storage_slot_commitment` off-chain and then pass it
    /// as an argument to the followup call to `finalize_transfer_to_private`.
    #[private]
    #['private]
    fn prepare_transfer_to_private(
        from: AztecAddress,
        to: AztecAddress,
        transient_storage_slot_randomness: Field
    ) {
        let to_keys = get_public_keys(to);
        let to_npk_m_hash = to_keys.npk_m.hash();
        let to_note_slot = storage.private_nfts.at(to).storage_slot;

        // We create a partial NFT note hiding point with unpopulated/zero token id for 'to'
        // TODO(#7775): Manually fetching the randomness here is not great. If we decide to include randomness in all
        // notes we could just inject it in macros.
        let note_randomness = unsafe {
            random()
        };
        let note_setup_payload = NFTNote::setup_payload().new(to_npk_m_hash, note_randomness, to_note_slot);

        // We encrypt and emit the partial note log
        encrypt_and_emit_partial_log(&mut context, note_setup_payload.log_plaintext, to_keys, to);

        // We make the msg_sender/transfer_preparer part of the slot preimage to ensure he cannot interfere with
        // non-sender's slots
        let transfer_preparer_storage_slot_commitment: Field = pedersen_hash(
            [context.msg_sender().to_field(), transient_storage_slot_randomness],
            TRANSIENT_STORAGE_SLOT_PEDERSEN_INDEX
        );
        // Then we hash the transfer preparer storage slot commitment with `from` and use that as the final slot
        // --> by hashing it with a `from` we ensure that `from` cannot interfere with slots not assigned to him.
        let slot: Field = pedersen_hash(
            [from.to_field(), transfer_preparer_storage_slot_commitment],
            TRANSIENT_STORAGE_SLOT_PEDERSEN_INDEX
        );

        NFT::at(context.this_address())._store_point_in_transient_storage(note_setup_payload.hiding_point, slot).enqueue(&mut context);
    }

    #[public]
    #['public]
    #['internal]
    fn _store_point_in_transient_storage(point: Point, slot: Field) {
        // We don't perform check for the overwritten value to be non-zero because the slots are siloed to `to`
        // and hence `to` can interfere only with his own execution.
        context.storage_write(slot, point);
    }

    /// Finalizes a transfer of NFT with `token_id` from public balance of `from` to a private balance of `to`.
    /// The transfer must be prepared by calling `prepare_transfer_to_private` first.
    /// The `transfer_preparer_storage_slot_commitment` has to be computed off-chain the same way as was done
    /// in the preparation call.
    #[public]
    #['public]
    fn finalize_transfer_to_private(
        token_id: Field,
        transfer_preparer_storage_slot_commitment: Field
    ) {
        // We don't need to support authwit here because `prepare_transfer_to_private` allows us to set arbitrary
        // `from` and `from` will always be the msg sender here.
        let from = context.msg_sender();
        let public_owners_storage = storage.public_owners.at(token_id);
        assert(public_owners_storage.read().eq(from), "invalid NFT owner");

        // Derive the slot from the transfer preparer storage slot commitment and the `from` address (declared
        // as `from` in this function)
        let hiding_point_slot = pedersen_hash(
            [from.to_field(), transfer_preparer_storage_slot_commitment],
            TRANSIENT_STORAGE_SLOT_PEDERSEN_INDEX
        );

        // Read the hiding point from "transient" storage and check it's not empty to ensure the transfer was prepared
        let hiding_point: Point = context.storage_read(hiding_point_slot);
        assert(!is_empty(hiding_point), "transfer not prepared");

        // Set the public NFT owner to zero
        public_owners_storage.write(AztecAddress::zero());

        // Finalize the partial note with the `token_id`
        let finalization_payload = NFTNote::finalization_payload().new(hiding_point, token_id);

        // We insert the finalization note hash
        context.push_note_hash(finalization_payload.note_hash);

        // We emit the `token_id` as unencrypted event such that the `NoteProcessor` can use it to reconstruct the note
        context.emit_unencrypted_log(finalization_payload.log);

        // At last we reset public storage to zero to achieve the effect of transient storage - kernels will squash
        // the writes
        context.storage_write(hiding_point_slot, Point::empty());
    }

    /**
     * Cancel a private authentication witness.
     * @param inner_hash The inner hash of the authwit to cancel.
     */
    #[private]
    #['private]
    fn cancel_authwit(inner_hash: Field) {
        let on_behalf_of = context.msg_sender();
        let nullifier = compute_authwit_nullifier(on_behalf_of, inner_hash);
        context.push_nullifier(nullifier);
    }

    #[private]
    #['private]
    fn transfer_in_private(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }

        let nfts = storage.private_nfts;

        let notes = nfts.at(from).pop_notes(
            NoteGetterOptions::new().select(NFTNote::properties().token_id, Comparator.EQ, token_id).set_limit(1)
        );
        assert(notes.len() == 1, "NFT not found when transferring");

        let from_ovpk_m = get_public_keys(from).ovpk_m;
        let to_keys = get_public_keys(to);

        let mut new_note = NFTNote::new(token_id, to_keys.npk_m.hash());
        nfts.at(to).insert(&mut new_note).emit(encode_and_encrypt_note(&mut context, from_ovpk_m, to_keys.ivpk_m, to));
    }

    #[private]
    #['private]
    fn transfer_to_public(from: AztecAddress, to: AztecAddress, token_id: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }

        let notes = storage.private_nfts.at(from).pop_notes(
            NoteGetterOptions::new().select(NFTNote::properties().token_id, Comparator.EQ, token_id).set_limit(1)
        );
        assert(notes.len() == 1, "NFT not found when transferring to public");

        NFT::at(context.this_address())._finish_transfer_to_public(to, token_id).enqueue(&mut context);
    }

    #[public]
    #['public]
    #['internal]
    fn _finish_transfer_to_public(to: AztecAddress, token_id: Field) {
        storage.public_owners.at(token_id).write(to);
    }

    // Returns zero address when the token does not have a public owner. Reverts if the token does not exist.
    #[public]
    #['public]
    #['view]
    fn owner_of(token_id: Field) -> AztecAddress {
        assert(storage.nft_exists.at(token_id).read(), "token does not exist");
        storage.public_owners.at(token_id).read()
    }

    /// Returns an array of token IDs owned by `owner` in private and a flag indicating whether a page limit was
    /// reached. Starts getting the notes from page with index `page_index`. Zero values in the array are placeholder
    /// values for non-existing notes.
    unconstrained fn get_private_nfts(owner: AztecAddress, page_index: u32) -> pub ([Field; MAX_NOTES_PER_PAGE], bool) {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let notes = storage.private_nfts.at(owner).view_notes(options.set_offset(offset));

        let mut owned_nft_ids = [0; MAX_NOTES_PER_PAGE];
        for i in 0..options.limit {
            if i < notes.len() {
                owned_nft_ids[i] = notes.get_unchecked(i).token_id;
            }
        }

        let page_limit_reached = notes.len() == options.limit;
        (owned_nft_ids, page_limit_reached)
    }
}
