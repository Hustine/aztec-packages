// A contract used for testing a random hodgepodge of small features from simulator and end-to-end tests.
use dep::aztec::macros::aztec;

#[aztec]
contract StatefulTest {
    use dep::aztec::prelude::{Map, PublicMutable, PrivateSet, AztecAddress, FunctionSelector};
    use dep::value_note::{balance_utils, utils::{increment, decrement}, value_note::ValueNote};
    use dep::aztec::{
        initializer::assert_is_initialized_private,
        macros::{storage::storage, functions::{private, public, initializer, noinitcheck, view}}
    };

    #[storage]
    struct Storage<Context> {
        notes: Map<AztecAddress, PrivateSet<ValueNote, Context>, Context>,
        public_values: Map<AztecAddress, PublicMutable<Field, Context>, Context>,
    }

    #[private]
    #['private]
    #['initializer]
    fn constructor(owner: AztecAddress, outgoing_viewer: AztecAddress, value: Field) {
        StatefulTest::at(context.this_address()).create_note_no_init_check(owner, outgoing_viewer, value).call(&mut context);
    }

    #[private]
    #['private]
    #['initializer]
    fn wrong_constructor() {
        let selector = FunctionSelector::from_signature("not_exists(Field)");
        let _res = context.call_public_function(context.this_address(), selector, [42]);
    }

    // Having _ignored_arg here as it makes the params the same as for the private constructor which makes
    // contract_class_registration tests way less cluttered. This is a test contract. Don't judge me.
    #[public]
    #['public]
    #['initializer]
    fn public_constructor(owner: AztecAddress, _ignored_arg: AztecAddress, value: Field) {
        StatefulTest::at(context.this_address()).increment_public_value_no_init_check(owner, value).call(&mut context);
    }

    #[private]
    #['private]
    fn create_note(owner: AztecAddress, outgoing_viewer: AztecAddress, value: Field) {
        if (value != 0) {
            let loc = storage.notes.at(owner);
            increment(loc, value, owner, outgoing_viewer);
        }
    }

    #[private]
    #['private]
    #['noinitcheck]
    fn create_note_no_init_check(owner: AztecAddress, outgoing_viewer: AztecAddress, value: Field) {
        if (value != 0) {
            let loc = storage.notes.at(owner);
            increment(loc, value, owner, outgoing_viewer);
        }
    }

    #[private]
    #['private]
    fn destroy_and_create(recipient: AztecAddress, amount: Field) {
        assert_is_initialized_private(&mut context);
        let sender = context.msg_sender();

        let sender_notes = storage.notes.at(sender);
        decrement(sender_notes, amount, sender, context.msg_sender());

        let recipient_notes = storage.notes.at(recipient);
        increment(recipient_notes, amount, recipient, context.msg_sender());
    }

    #[private]
    #['private]
    #['noinitcheck]
    fn destroy_and_create_no_init_check(recipient: AztecAddress, amount: Field) {
        let sender = context.msg_sender();

        let sender_notes = storage.notes.at(sender);
        decrement(sender_notes, amount, sender, context.msg_sender());

        let recipient_notes = storage.notes.at(recipient);
        increment(recipient_notes, amount, recipient, context.msg_sender());
    }

    #[public]
    #['public]
    fn increment_public_value(owner: AztecAddress, value: Field) {
        let loc = storage.public_values.at(owner);
        loc.write(loc.read() + value);
    }

    #[public]
    #['public]
    #['noinitcheck]
    fn increment_public_value_no_init_check(owner: AztecAddress, value: Field) {
        let loc = storage.public_values.at(owner);
        loc.write(loc.read() + value);
    }

    unconstrained fn summed_values(owner: AztecAddress) -> pub Field {
        let owner_balance = storage.notes.at(owner);

        // docs:start:get_balance
        // Return the sum of all notes in the set.
        balance_utils::get_balance(owner_balance)
        // docs:end:get_balance
    }

    #[public]
    #['public]
    #['noinitcheck]
    #['view]
    fn get_public_value(owner: AztecAddress) -> pub Field {
        storage.public_values.at(owner).read()
    }
}
