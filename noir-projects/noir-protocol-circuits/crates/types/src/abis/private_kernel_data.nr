use crate::{
    abis::kernel_circuit_public_inputs::PrivateKernelCircuitPublicInputs,
    constants::{PRIVATE_KERNEL_RESET_INDEX, VK_TREE_HEIGHT},
    merkle_tree::membership::assert_check_membership,
    recursion::{verification_key::ClientIVCVerificationKey}, utils::arrays::find_index_hint
};

pub struct PrivateKernelData {
    public_inputs: PrivateKernelCircuitPublicInputs,
    vk: ClientIVCVerificationKey,
    vk_index: u32,
    vk_path: [Field; VK_TREE_HEIGHT],
}

impl PrivateKernelData {
    fn validate_in_vk_tree<let N: u32>(self, allowed_indices: [u32; N]) {
        let index_in_allowed_list = if self.vk_index >= PRIVATE_KERNEL_RESET_INDEX {
            // Kernel circuits only need to include PRIVATE_KERNEL_RESET_INDEX in the list to allow all private kernel reset variants.
            PRIVATE_KERNEL_RESET_INDEX
        } else {
            self.vk_index
        };
        let index_hint = unsafe {
            find_index_hint(allowed_indices, |index: u32| index == index_in_allowed_list)
        };
        assert(index_hint < N, "Invalid vk index");
        assert_eq(allowed_indices[index_hint], index_in_allowed_list, "Invalid vk index");

        assert_check_membership(
            self.vk.hash,
            self.vk_index as Field,
            self.vk_path,
            self.public_inputs.constants.vk_tree_root
        );
    }
}

pub struct PrivateKernelDataWithoutPublicInputs {
    vk: ClientIVCVerificationKey,
    vk_index: u32,
    vk_path: [Field; VK_TREE_HEIGHT],
}

impl PrivateKernelDataWithoutPublicInputs {
    pub fn to_private_kernel_data(self, public_inputs: PrivateKernelCircuitPublicInputs) -> PrivateKernelData {
        PrivateKernelData { public_inputs, vk: self.vk, vk_index: self.vk_index, vk_path: self.vk_path }
    }
}
