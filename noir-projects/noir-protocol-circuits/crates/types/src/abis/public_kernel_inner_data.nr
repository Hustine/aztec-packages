use crate::{
    abis::kernel_circuit_public_inputs::VMCircuitPublicInputs,
    recursion::{proof::NestedRecursiveProof, verification_key::HonkVerificationKey, traits::Verifiable}
};

pub struct PublicKernelInnerData {
    public_inputs: VMCircuitPublicInputs,
    proof: NestedRecursiveProof,
    vk: HonkVerificationKey,
}

impl Verifiable for PublicKernelInnerData {
    fn verify(self) {
        let inputs = VMCircuitPublicInputs::serialize(self.public_inputs);
        std::verify_proof(self.vk.key, self.proof.fields, inputs, self.vk.hash);
    }
}
