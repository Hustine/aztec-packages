mod asset;

use dep::aztec::macros::aztec;

#[aztec]
contract PriceFeed {
    use dep::aztec::prelude::{Map, PublicMutable};
    use crate::asset::Asset;

    use dep::aztec::macros::{storage::storage, functions::{public, view}};

    // Storage structure, containing all storage, and specifying what slots they use.
    #[storage]
    struct Storage<Context> {
        assets: Map<Field, PublicMutable<Asset, Context>, Context>,
    }

    #[public]
    #['public]
    fn set_price(asset_id: Field, price: Field) {
        let asset = storage.assets.at(asset_id);
        asset.write(Asset { price: U128::from_integer(price) });
    }

    #[public]
    #['public]
    #['view]
    fn get_price(asset_id: Field) -> Asset {
        storage.assets.at(asset_id).read()
    }
}
