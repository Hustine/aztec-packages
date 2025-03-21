mod lib;

use dep::aztec::macros::aztec;

#[aztec]
contract FeeJuice {
    use dep::aztec::{
        protocol_types::{address::{AztecAddress, EthAddress}, constants::FEE_JUICE_INITIAL_MINT},
        state_vars::{SharedImmutable, PublicMutable, Map},
        macros::{storage::storage, functions::{private, public, view, internal}}
    };

    use crate::lib::get_bridge_gas_msg_hash;

    #[storage]
    struct Storage<Context> {
        // This map is accessed directly by protocol circuits to check balances for fee payment.
        // Do not change this storage layout unless you also update the base rollup circuits.
        balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
        portal_address: SharedImmutable<EthAddress, Context>,
    }

    // Not flagged as initializer to reduce cost of checking init nullifier in all functions.
    // This function should be called as entrypoint to initialize the contract by minting itself funds.
    #[private]
    #['private]
    fn initialize(portal_address: EthAddress) {
        // Validate contract class parameters are correct
        let self = context.this_address();

        // Increase self balance and set as fee payer, and end setup
        FeeJuice::at(self)._increase_public_balance(self, FEE_JUICE_INITIAL_MINT).enqueue(&mut context);
        context.set_as_fee_payer();
        context.end_setup();

        // Enqueue call to set the portal address
        FeeJuice::at(self).set_portal(portal_address).enqueue(&mut context);
    }

    // We purposefully not set this function as an initializer so we do not bind
    // the contract to a specific L1 portal address, since the Fee Juice address
    // is a hardcoded constant in the rollup circuits.
    #[public]
    #['public]
    fn set_portal(portal_address: EthAddress) {
        assert(storage.portal_address.read_public().is_zero());
        storage.portal_address.initialize(portal_address);
    }

    #[private]
    #['private]
    fn claim(to: AztecAddress, amount: Field, secret: Field) {
        let content_hash = get_bridge_gas_msg_hash(to, amount);
        let portal_address = storage.portal_address.read_private();
        assert(!portal_address.is_zero());

        // Consume message and emit nullifier
        context.consume_l1_to_l2_message(content_hash, secret, portal_address);

        // TODO(palla/gas) Emit an unencrypted log to announce which L1 to L2 message has been claimed
        // Otherwise, we cannot trace L1 deposits to their corresponding claims on L2

        FeeJuice::at(context.this_address())._increase_public_balance(to, amount).enqueue(&mut context);
    }

    #[public]
    #['public]
    #['internal]
    fn _increase_public_balance(to: AztecAddress, amount: Field) {
        let new_balance = storage.balances.at(to).read().add(U128::from_integer(amount));
        storage.balances.at(to).write(new_balance);
    }

    #[public]
    #['public]
    #['view]
    fn check_balance(fee_limit: Field) {
        let fee_limit = U128::from_integer(fee_limit);
        assert(storage.balances.at(context.msg_sender()).read() >= fee_limit, "Balance too low");
    }

    // utility function for testing
    #[public]
    #['public]
    #['view]
    fn balance_of_public(owner: AztecAddress) -> pub Field {
        storage.balances.at(owner).read().to_field()
    }
}
