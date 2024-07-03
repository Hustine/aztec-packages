import { type ContractArtifact, type FunctionSelector, FunctionType } from '@aztec/foundation/abi';
import { Fr } from '@aztec/foundation/fields';
import { createDebugLogger } from '@aztec/foundation/log';
import {
  type ContractClassPublic,
  type ExecutablePrivateFunctionWithMembershipProof,
  type PrivateFunctionMembershipProof,
} from '@aztec/types/contracts';

import { computeRootFromSiblingPath } from '../merkle/index.js';
import {
  computeArtifactFunctionTree,
  computeArtifactHash,
  computeArtifactHashPreimage,
  computeFunctionArtifactHash,
  computeFunctionMetadataHash,
  getArtifactMerkleTreeHasher,
} from './artifact_hash.js';
import { getContractClassPrivateFunctionFromArtifact } from './contract_class.js';
import { computePrivateFunctionLeaf, computePrivateFunctionsTree } from './private_function.js';

/**
 * Creates a membership proof for a private function in a contract class, to be verified via `isValidPrivateFunctionMembershipProof`.
 * @param selector - Selector of the function to create the proof for.
 * @param artifact - Artifact of the contract class where the function is defined.
 */
export function createPrivateFunctionMembershipProof(
  selector: FunctionSelector,
  artifact: ContractArtifact,
): PrivateFunctionMembershipProof {
  const log = createDebugLogger('aztec:circuits:function_membership_proof');

  // Locate private function definition and artifact
  const privateFunctions = artifact.functions
    .filter(fn => fn.functionType === FunctionType.PRIVATE)
    .map(getContractClassPrivateFunctionFromArtifact);
  const privateFunction = privateFunctions.find(fn => fn.selector.equals(selector));
  const privateFunctionArtifact = artifact.functions.find(fn => selector.equals(fn));
  if (!privateFunction || !privateFunctionArtifact) {
    throw new Error(`Private function with selector ${selector.toString()} not found`);
  }

  // Compute preimage for the artifact hash
  const { unconstrainedFunctionRoot: unconstrainedFunctionsArtifactTreeRoot, metadataHash: artifactMetadataHash } =
    computeArtifactHashPreimage(artifact);

  // We need two sibling paths because private function information is split across two trees:
  // The "private function tree" captures the selectors and verification keys, and is used in the kernel circuit for verifying the proof generated by the app circuit.
  const functionLeaf = computePrivateFunctionLeaf(privateFunction);
  const functionsTree = computePrivateFunctionsTree(privateFunctions);
  const functionsTreeLeafIndex = functionsTree.getIndex(functionLeaf);
  const functionsTreeSiblingPath = functionsTree.getSiblingPath(functionsTreeLeafIndex).map(Fr.fromBuffer);

  // And the "artifact tree" captures function bytecode and metadata, and is used by the pxe to check that its executing the code it's supposed to be executing, but it never goes into circuits.
  const functionMetadataHash = computeFunctionMetadataHash(privateFunctionArtifact);
  const functionArtifactHash = computeFunctionArtifactHash({ ...privateFunctionArtifact, functionMetadataHash });
  const artifactTree = computeArtifactFunctionTree(artifact, FunctionType.PRIVATE)!;
  const artifactTreeLeafIndex = artifactTree.getIndex(functionArtifactHash.toBuffer());
  const artifactTreeSiblingPath = artifactTree.getSiblingPath(artifactTreeLeafIndex).map(Fr.fromBuffer);

  log.debug(`Computed proof for private function with selector ${selector.toString()}`, {
    functionArtifactHash,
    functionMetadataHash,
    functionLeaf: '0x' + functionLeaf.toString('hex'),
    artifactMetadataHash,
    privateFunctionsTreeRoot: '0x' + functionsTree.root.toString('hex'),
    unconstrainedFunctionsArtifactTreeRoot,
    artifactFunctionTreeSiblingPath: artifactTreeSiblingPath.map(fr => fr.toString()).join(','),
    privateFunctionTreeSiblingPath: functionsTreeSiblingPath.map(fr => fr.toString()).join(','),
  });

  return {
    artifactTreeSiblingPath,
    artifactTreeLeafIndex,
    artifactMetadataHash,
    functionMetadataHash,
    unconstrainedFunctionsArtifactTreeRoot,
    privateFunctionTreeSiblingPath: functionsTreeSiblingPath,
    privateFunctionTreeLeafIndex: functionsTreeLeafIndex,
  };
}

/**
 * Verifies that a private function with a membership proof as emitted by the ClassRegisterer contract is valid,
 * as defined in the protocol specs at contract-deployment/classes:
 *
 * ```
 * // Load contract class from local db
 * contract_class = db.get_contract_class(contract_class_id)
 *
 * // Compute function leaf and assert it belongs to the private functions tree
 * function_leaf = pedersen([selector as Field, vk_hash], GENERATOR__FUNCTION_LEAF)
 * computed_private_function_tree_root = compute_root(function_leaf, private_function_tree_sibling_path)
 * assert computed_private_function_tree_root == contract_class.private_function_root
 *
 * // Compute artifact leaf and assert it belongs to the artifact
 * artifact_function_leaf = sha256(selector, metadata_hash, sha256(bytecode))
 * computed_artifact_private_function_tree_root = compute_root(artifact_function_leaf, artifact_function_tree_sibling_path)
 * computed_artifact_hash = sha256(computed_artifact_private_function_tree_root, unconstrained_functions_artifact_tree_root, artifact_metadata_hash)
 * assert computed_artifact_hash == contract_class.artifact_hash
 * ```
 * @param fn - Function to check membership proof for.
 * @param contractClass - In which contract class the function is expected to be.
 */
export function isValidPrivateFunctionMembershipProof(
  fn: ExecutablePrivateFunctionWithMembershipProof,
  contractClass: Pick<ContractClassPublic, 'privateFunctionsRoot' | 'artifactHash'>,
) {
  const log = createDebugLogger('aztec:circuits:function_membership_proof');

  // Check private function tree membership
  const functionLeaf = computePrivateFunctionLeaf(fn);
  const computedPrivateFunctionTreeRoot = Fr.fromBuffer(
    computeRootFromSiblingPath(
      functionLeaf,
      fn.privateFunctionTreeSiblingPath.map(fr => fr.toBuffer()),
      fn.privateFunctionTreeLeafIndex,
    ),
  );
  if (!contractClass.privateFunctionsRoot.equals(computedPrivateFunctionTreeRoot)) {
    log.debug(`Private function tree root mismatch`, {
      expectedPrivateFunctionTreeRoot: contractClass.privateFunctionsRoot,
      computedPrivateFunctionTreeRoot: computedPrivateFunctionTreeRoot,
      computedFunctionLeaf: '0x' + functionLeaf.toString('hex'),
    });
    return false;
  }

  // Check artifact hash
  const functionArtifactHash = computeFunctionArtifactHash(fn);
  const computedArtifactPrivateFunctionTreeRoot = Fr.fromBuffer(
    computeRootFromSiblingPath(
      functionArtifactHash.toBuffer(),
      fn.artifactTreeSiblingPath.map(fr => fr.toBuffer()),
      fn.artifactTreeLeafIndex,
      getArtifactMerkleTreeHasher(),
    ),
  );
  const computedArtifactHash = computeArtifactHash({
    privateFunctionRoot: computedArtifactPrivateFunctionTreeRoot,
    unconstrainedFunctionRoot: fn.unconstrainedFunctionsArtifactTreeRoot,
    metadataHash: fn.artifactMetadataHash,
  });
  if (!contractClass.artifactHash.equals(computedArtifactHash)) {
    log.debug(`Artifact hash mismatch`, {
      expected: contractClass.artifactHash,
      computedArtifactHash,
      computedFunctionArtifactHash: functionArtifactHash,
      computedArtifactPrivateFunctionTreeRoot,
      unconstrainedFunctionRoot: fn.unconstrainedFunctionsArtifactTreeRoot,
      metadataHash: fn.artifactMetadataHash,
      artifactFunctionTreeSiblingPath: fn.artifactTreeSiblingPath.map(fr => fr.toString()).join(','),
    });
    return false;
  }

  return true;
}