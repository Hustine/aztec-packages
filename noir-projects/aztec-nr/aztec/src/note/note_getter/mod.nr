use dep::protocol_types::{constants::{MAX_NOTE_HASH_READ_REQUESTS_PER_CALL, GET_NOTES_ORACLE_RETURN_LENGTH}};
use crate::context::PrivateContext;
use crate::note::{
    constants::{GET_NOTE_ORACLE_RETURN_LENGTH, VIEW_NOTE_ORACLE_RETURN_LENGTH},
    note_getter_options::{NoteGetterOptions, Select, Sort, SortOrder, NoteStatus, PropertySelector},
    note_interface::{NoteInterface, NullifiableNote}, note_viewer_options::NoteViewerOptions,
    utils::compute_note_hash_for_read_request
};
use crate::oracle;
use crate::utils::comparison::compare;

pub use crate::note::constants::MAX_NOTES_PER_PAGE;

mod test;

fn extract_property_value_from_selector<let N: u32>(
    serialized_note: [Field; N],
    selector: PropertySelector
) -> Field {
    // Selectors use PropertySelectors in order to locate note properties inside the serialized note.
    // This allows easier packing and custom (de)serialization schemas. A note property is located
    // inside the serialized note using the index inside the array, a byte offset and a length.
    let value: [u8; 32] = serialized_note[selector.index].to_be_bytes();
    let offset = selector.offset;
    let length = selector.length;
    let mut value_field = 0 as Field;
    let mut acc: Field = 1;
    for i in 0..32 {
        if i < length {
            value_field += value[31 + offset - i] as Field * acc;
            acc = acc * 256;
        }
    }
    value_field
}

fn check_note_header<Note, let N: u32>(
    context: PrivateContext,
    storage_slot: Field,
    note: Note
) where Note: NoteInterface<N> {
    let header = note.get_header();
    let contract_address = context.this_address();
    assert(header.contract_address.eq(contract_address), "Mismatch note header contract address.");
    assert(header.storage_slot == storage_slot, "Mismatch note header storage slot.");
}

fn check_note_fields<let N: u32>(
    serialized_note: [Field; N],
    selects: BoundedVec<Option<Select>, N>
) {
    for i in 0..selects.len {
        let select = selects.get_unchecked(i).unwrap_unchecked();
        let value_field = extract_property_value_from_selector(serialized_note, select.property_selector);

        assert(
            compare(value_field, select.comparator, select.value.to_field()), "Mismatch return note field."
        );
    }
}

fn check_notes_order<let N: u32>(
    fields_0: [Field; N],
    fields_1: [Field; N],
    sorts: BoundedVec<Option<Sort>, N>
) {
    for i in 0..sorts.len {
        let sort = sorts.get_unchecked(i).unwrap_unchecked();
        let field_0 = extract_property_value_from_selector(fields_0, sort.property_selector);
        let field_1 = extract_property_value_from_selector(fields_1, sort.property_selector);
        let eq = field_0 == field_1;
        let lt = field_0.lt(field_1);
        if sort.order == SortOrder.ASC {
            assert(eq | lt, "Return notes not sorted in ascending order.");
        } else if !eq {
            assert(!lt, "Return notes not sorted in descending order.");
        }
    }
}

pub fn get_note<Note, let N: u32>(
    context: &mut PrivateContext,
    storage_slot: Field
) -> (Note, Field) where Note: NoteInterface<N> + NullifiableNote {
    let note = unsafe {
        get_note_internal(storage_slot)
    };

    // Constraining that we got a valid note from the oracle is fairly straightforward: all we need to do is check that
    // the metadata is correct, and that the note exists.
    check_note_header(*context, storage_slot, note);

    let note_hash_for_read_request = compute_note_hash_for_read_request(note);
    context.push_note_hash_read_request(note_hash_for_read_request);

    (note, note_hash_for_read_request)
}

pub fn get_notes<Note, let N: u32, PREPROCESSOR_ARGS, FILTER_ARGS>(
    context: &mut PrivateContext,
    storage_slot: Field,
    options: NoteGetterOptions<Note, N, PREPROCESSOR_ARGS, FILTER_ARGS>
) -> (BoundedVec<Note, MAX_NOTE_HASH_READ_REQUESTS_PER_CALL>, BoundedVec<Field, MAX_NOTE_HASH_READ_REQUESTS_PER_CALL>) where Note: NoteInterface<N> + NullifiableNote + Eq {
    let opt_notes = unsafe {
        get_notes_internal(storage_slot, options)
    };

    // We apply the constraints in a separate function instead of inlining them here to make it easier to test that
    // these checks correctly reject bad notes.
    constrain_get_notes_internal(context, storage_slot, opt_notes, options)
}

unconstrained fn apply_preprocessor<Note, PREPROCESSOR_ARGS>(
    notes: [Option<Note>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL],
    preprocessor: fn([Option<Note>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL], PREPROCESSOR_ARGS) -> [Option<Note>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL],
    preprocessor_args: PREPROCESSOR_ARGS
) -> [Option<Note>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL] {
    preprocessor(notes, preprocessor_args)
}

fn constrain_get_notes_internal<Note, let N: u32, PREPROCESSOR_ARGS, FILTER_ARGS>(
    context: &mut PrivateContext,
    storage_slot: Field,
    opt_notes: [Option<Note>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL],
    options: NoteGetterOptions<Note, N, PREPROCESSOR_ARGS, FILTER_ARGS>
) -> (BoundedVec<Note, MAX_NOTE_HASH_READ_REQUESTS_PER_CALL>, BoundedVec<Field, MAX_NOTE_HASH_READ_REQUESTS_PER_CALL>) where Note: NoteInterface<N> + NullifiableNote + Eq {
    // The filter is applied first to avoid pushing note read requests for notes we're not interested in. Note that
    // while the filter function can technically mutate the contents of the notes (as opposed to simply removing some),
    // the private kernel will later validate that these note actually exist, so transformations would cause for that
    // check to fail.
    let filter_fn = options.filter;
    let filter_args = options.filter_args;
    let filtered_notes = filter_fn(opt_notes, filter_args);

    let notes = crate::utils::collapse_array(filtered_notes);
    let mut note_hashes: BoundedVec<Field, MAX_NOTE_HASH_READ_REQUESTS_PER_CALL> = BoundedVec::new();

    // We have now collapsed the sparse array of Options into a BoundedVec. This is a more ergonomic type and also
    // results in reduced gate counts when setting a limit value, since we guarantee that the limit is an upper bound
    // for the runtime length, and can therefore have fewer loop iterations.
    assert(notes.len() <= options.limit, "Got more notes than limit.");

    let mut prev_fields = [0; N];
    for i in 0..options.limit {
        if i < notes.len() {
            let note = notes.get_unchecked(i);
            let fields = note.serialize_content();
            check_note_header(*context, storage_slot, note);
            check_note_fields(fields, options.selects);
            if i != 0 {
                check_notes_order(prev_fields, fields, options.sorts);
            }
            prev_fields = fields;

            let note_hash_for_read_request = compute_note_hash_for_read_request(note);
            // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1410): test to ensure
            // failure if malicious oracle injects 0 nonce here for a "pre-existing" note.
            context.push_note_hash_read_request(note_hash_for_read_request);
            note_hashes.push(note_hash_for_read_request);
        };
    }

    (notes, note_hashes)
}

unconstrained fn get_note_internal<Note, let N: u32>(storage_slot: Field) -> Note where Note: NoteInterface<N> {
    let placeholder_note = [Option::none()];
    let placeholder_fields = [0; GET_NOTE_ORACLE_RETURN_LENGTH];
    let placeholder_note_length = [0; N];
    oracle::notes::get_notes(
        storage_slot,
        0,
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        1, // limit
        0, // offset
        NoteStatus.ACTIVE,
        placeholder_note,
        placeholder_fields,
        placeholder_note_length
    )[0].expect(f"Failed to get a note") // Notice: we don't allow dummies to be returned from get_note (singular).
}

unconstrained fn get_notes_internal<Note, let N: u32, PREPROCESSOR_ARGS, FILTER_ARGS>(
    storage_slot: Field,
    options: NoteGetterOptions<Note, N, PREPROCESSOR_ARGS, FILTER_ARGS>
) -> [Option<Note>; MAX_NOTE_HASH_READ_REQUESTS_PER_CALL] where Note: NoteInterface<N> {
    // This function simply performs some transformations from NoteGetterOptions into the types required by the oracle.

    let (num_selects, select_by_indexes, select_by_offsets, select_by_lengths, select_values, select_comparators, sort_by_indexes, sort_by_offsets, sort_by_lengths, sort_order) = flatten_options(options.selects, options.sorts);
    let placeholder_opt_notes = [Option::none(); MAX_NOTE_HASH_READ_REQUESTS_PER_CALL];
    let placeholder_fields = [0; GET_NOTES_ORACLE_RETURN_LENGTH];
    let placeholder_note_length = [0; N];

    let opt_notes = oracle::notes::get_notes(
        storage_slot,
        num_selects,
        select_by_indexes,
        select_by_offsets,
        select_by_lengths,
        select_values,
        select_comparators,
        sort_by_indexes,
        sort_by_offsets,
        sort_by_lengths,
        sort_order,
        options.limit,
        options.offset,
        options.status,
        placeholder_opt_notes,
        placeholder_fields,
        placeholder_note_length
    );

    apply_preprocessor(opt_notes, options.preprocessor, options.preprocessor_args)
}

pub unconstrained fn view_notes<Note, let N: u32>(
    storage_slot: Field,
    options: NoteViewerOptions<Note, N>
) -> BoundedVec<Note, MAX_NOTES_PER_PAGE> where Note: NoteInterface<N> {
    let (num_selects, select_by_indexes, select_by_offsets, select_by_lengths, select_values, select_comparators, sort_by_indexes, sort_by_offsets, sort_by_lengths, sort_order) = flatten_options(options.selects, options.sorts);
    let placeholder_opt_notes = [Option::none(); MAX_NOTES_PER_PAGE];
    let placeholder_fields = [0; VIEW_NOTE_ORACLE_RETURN_LENGTH];
    let placeholder_note_length = [0; N];

    let notes_array = oracle::notes::get_notes(
        storage_slot,
        num_selects,
        select_by_indexes,
        select_by_offsets,
        select_by_lengths,
        select_values,
        select_comparators,
        sort_by_indexes,
        sort_by_offsets,
        sort_by_lengths,
        sort_order,
        options.limit,
        options.offset,
        options.status,
        placeholder_opt_notes,
        placeholder_fields,
        placeholder_note_length
    );

    let mut notes = BoundedVec::new();
    for i in 0..notes_array.len() {
        if notes_array[i].is_some() {
            notes.push(notes_array[i].unwrap_unchecked());
        }
    }

    notes
}

unconstrained fn flatten_options<let N: u32>(
    selects: BoundedVec<Option<Select>, N>,
    sorts: BoundedVec<Option<Sort>, N>
) -> (u8, [u8; N], [u8; N], [u8; N], [Field; N], [u8; N], [u8; N], [u8; N], [u8; N], [u8; N]) {
    let mut num_selects = 0;
    let mut select_by_indexes = [0; N];
    let mut select_by_offsets = [0; N];
    let mut select_by_lengths = [0; N];
    let mut select_values = [0; N];
    let mut select_comparators = [0; N];

    for i in 0..selects.len {
        let select = selects.get(i);
        if select.is_some() {
            select_by_indexes[num_selects] = select.unwrap_unchecked().property_selector.index;
            select_by_offsets[num_selects] = select.unwrap_unchecked().property_selector.offset;
            select_by_lengths[num_selects] = select.unwrap_unchecked().property_selector.length;
            select_values[num_selects] = select.unwrap_unchecked().value;
            select_comparators[num_selects] = select.unwrap_unchecked().comparator;
            num_selects += 1;
        };
    }

    let mut sort_by_indexes = [0; N];
    let mut sort_by_offsets = [0; N];
    let mut sort_by_lengths = [0; N];
    let mut sort_order = [0; N];
    for i in 0..sorts.len {
        let sort = sorts.get(i);
        if sort.is_some() {
            sort_by_indexes[i] = sort.unwrap_unchecked().property_selector.index;
            sort_by_offsets[i] = sort.unwrap_unchecked().property_selector.offset;
            sort_by_lengths[i] = sort.unwrap_unchecked().property_selector.length;
            sort_order[i] = sort.unwrap_unchecked().order;
        };
    }

    (
        num_selects, select_by_indexes, select_by_offsets, select_by_lengths, select_values, select_comparators, sort_by_indexes, sort_by_offsets, sort_by_lengths, sort_order
    )
}
