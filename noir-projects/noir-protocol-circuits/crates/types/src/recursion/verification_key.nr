use crate::{
    traits::{Serialize, Deserialize, Empty},
    constants::{HONK_VERIFICATION_KEY_LENGTH_IN_FIELDS, CLIENT_IVC_VERIFICATION_KEY_LENGTH_IN_FIELDS}
};

pub struct VerificationKey<let N: u32> {
    key: [Field; N],
    hash: Field,
}

impl<let N: u32> Serialize<N + 1> for VerificationKey<N> {
    fn serialize(self) -> [Field; N + 1] {
        let mut fields = [0; N + 1];
        for i in 0..N {
            fields[i] = self.key[i];
        }
        fields[N] = self.hash;
        fields
    }
}

impl<let N: u32> Deserialize<N + 1> for VerificationKey<N> {
    fn deserialize(fields: [Field; N+1]) -> Self {
        let mut key = VerificationKey::empty();
        for i in 0..N {
            key.key[i] = fields[i];
        }
        key.hash = fields[N];
        key
    }
}

impl<let N: u32> Empty for VerificationKey<N> {
    fn empty() -> Self {
        VerificationKey { hash: 0, key: [0; N] }
    }
}

impl<let N: u32> Eq for VerificationKey<N> {
    fn eq(self, other: Self) -> bool {
        (self.hash == other.hash) & (self.key == other.key)
    }
}

type HonkVerificationKey = VerificationKey<HONK_VERIFICATION_KEY_LENGTH_IN_FIELDS>;
type ClientIVCVerificationKey = VerificationKey<CLIENT_IVC_VERIFICATION_KEY_LENGTH_IN_FIELDS>;

#[test]
fn serialization_of_empty() {
    let key: VerificationKey<20> = VerificationKey::empty();
    let serialized = key.serialize();
    let deserialized = VerificationKey::deserialize(serialized);
    assert(key.eq(deserialized));
}
