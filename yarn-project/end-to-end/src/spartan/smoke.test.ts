import { type PXE, createCompatibleClient } from '@aztec/aztec.js';
import { createDebugLogger } from '@aztec/foundation/log';
import { RollupAbi } from '@aztec/l1-artifacts';

import { createPublicClient, getAddress, getContract, http } from 'viem';
import { foundry } from 'viem/chains';

const { PXE_URL } = process.env;
if (!PXE_URL) {
  throw new Error('PXE_URL env variable must be set');
}
const debugLogger = createDebugLogger('aztec:spartan-test:smoke');
// const userLog = createConsoleLogger();

describe('smoke test', () => {
  let pxe: PXE;
  beforeAll(async () => {
    pxe = await createCompatibleClient(PXE_URL, debugLogger);
  });
  it('should be able to get node enr', async () => {
    const info = await pxe.getNodeInfo();
    expect(info).toBeDefined();
    // expect enr to be a string starting with 'enr:-'
    expect(info.enr).toMatch(/^enr:-/);
  });

  // Leaving this test skipped commented out because it requires the ethereum node
  // to be running and forwarded, e.g.
  // kubectl port-forward -n smoke service/spartan-aztec-network-ethereum 8545:8545
  // also because it assumes foundry.

  it.skip('should be able to get rollup info', async () => {
    const info = await pxe.getNodeInfo();
    const publicClient = createPublicClient({
      chain: foundry,
      transport: http('http://localhost:8545'),
    });

    const rollupContract = getContract({
      address: getAddress(info.l1ContractAddresses.rollupAddress.toString()),
      abi: RollupAbi,
      client: publicClient,
    });

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [pendingBlockNum, pendingArchive, provenBlockNum, provenArchive, myArchive, provenEpochNumber] =
      await rollupContract.read.status([60n]);
    // console.log('pendingBlockNum', pendingBlockNum.toString());
    // console.log('pendingArchive', pendingArchive.toString());
    // console.log('provenBlockNum', provenBlockNum.toString());
    // console.log('provenArchive', provenArchive.toString());
    // console.log('myArchive', myArchive.toString());
    // console.log('provenEpochNumber', provenEpochNumber.toString());
  });
});
