import { keccak256, keccakf1600, pedersenHash, sha256Compression } from '@aztec/foundation/crypto';

import { type AvmContext } from '../avm_context.js';
import { Field, type Uint8, Uint32, Uint64 } from '../avm_memory_types.js';
import { initContext, randomMemoryBytes, randomMemoryFields, randomMemoryUint32s } from '../fixtures/index.js';
import { Addressing, AddressingMode } from './addressing_mode.js';
import { Keccak, KeccakF1600, Pedersen, Poseidon2, Sha256Compression } from './hashing.js';

describe('Hashing Opcodes', () => {
  let context: AvmContext;

  beforeEach(async () => {
    context = initContext();
  });

  describe('Poseidon2', () => {
    it('Should (de)serialize correctly', () => {
      const buf = Buffer.from([
        Poseidon2.opcode, // opcode
        1, // indirect
        ...Buffer.from('1234', 'hex'), // inputStateOffset
        ...Buffer.from('2345', 'hex'), // outputStateOffset
      ]);
      const inst = new Poseidon2(/*indirect=*/ 1, /*dstOffset=*/ 0x1234, /*messageOffset=*/ 0x2345);

      expect(Poseidon2.deserialize(buf)).toEqual(inst);
      expect(inst.serialize()).toEqual(buf);
    });

    it('Should hash correctly - direct', async () => {
      const indirect = 0;
      const inputState = [new Field(1n), new Field(2n), new Field(3n), new Field(4n)];
      const inputStateOffset = 0;
      const outputStateOffset = 0;
      context.machineState.memory.setSlice(inputStateOffset, inputState);

      await new Poseidon2(indirect, inputStateOffset, outputStateOffset).execute(context);

      const result = context.machineState.memory.getSlice(outputStateOffset, 4);
      expect(result).toEqual([
        new Field(0x224785a48a72c75e2cbb698143e71d5d41bd89a2b9a7185871e39a54ce5785b1n),
        new Field(0x225bb800db22c4f4b09ace45cb484d42b0dd7dfe8708ee26aacde6f2c1fb2cb8n),
        new Field(0x1180f4260e60b4264c987b503075ea8374b53ed06c5145f8c21c2aadb5087d21n),
        new Field(0x16c877b5b9c04d873218804ccbf65d0eeb12db447f66c9ca26fec380055df7e9n),
      ]);
    });

    it('Should hash correctly - indirect', async () => {
      const indirect = new Addressing([AddressingMode.INDIRECT, AddressingMode.INDIRECT]).toWire();
      const inputState = [new Field(1n), new Field(2n), new Field(3n), new Field(4n)];
      const inputStateOffset = 0;
      const inputStateOffsetReal = 10;
      const outputStateOffset = 0;
      const outputStateOffsetReal = 10;
      context.machineState.memory.set(inputStateOffset, new Uint32(inputStateOffsetReal));
      context.machineState.memory.setSlice(inputStateOffsetReal, inputState);

      await new Poseidon2(indirect, inputStateOffset, outputStateOffset).execute(context);

      const result = context.machineState.memory.getSlice(outputStateOffsetReal, 4);
      expect(result).toEqual([
        new Field(0x224785a48a72c75e2cbb698143e71d5d41bd89a2b9a7185871e39a54ce5785b1n),
        new Field(0x225bb800db22c4f4b09ace45cb484d42b0dd7dfe8708ee26aacde6f2c1fb2cb8n),
        new Field(0x1180f4260e60b4264c987b503075ea8374b53ed06c5145f8c21c2aadb5087d21n),
        new Field(0x16c877b5b9c04d873218804ccbf65d0eeb12db447f66c9ca26fec380055df7e9n),
      ]);
    });
  });

  describe('Keccak', () => {
    it('Should (de)serialize correctly', () => {
      const buf = Buffer.from([
        Keccak.opcode, // opcode
        1, // indirect
        ...Buffer.from('12345678', 'hex'), // dstOffset
        ...Buffer.from('23456789', 'hex'), // messageOffset
        ...Buffer.from('3456789a', 'hex'), // messageSizeOffset
      ]);
      const inst = new Keccak(
        /*indirect=*/ 1,
        /*dstOffset=*/ 0x12345678,
        /*messageOffset=*/ 0x23456789,
        /*messageSizeOffset=*/ 0x3456789a,
      );

      expect(Keccak.deserialize(buf)).toEqual(inst);
      expect(inst.serialize()).toEqual(buf);
    });

    it('Should hash correctly - direct', async () => {
      const args = randomMemoryBytes(10);
      const indirect = 0;
      const messageOffset = 0;
      const messageSizeOffset = 15;
      const dstOffset = 20;
      context.machineState.memory.set(messageSizeOffset, new Uint32(args.length));
      context.machineState.memory.setSlice(messageOffset, args);

      await new Keccak(indirect, dstOffset, messageOffset, messageSizeOffset).execute(context);

      const resultBuffer = Buffer.concat(
        context.machineState.memory.getSliceAs<Uint8>(dstOffset, 32).map(byte => byte.toBuffer()),
      );
      const inputBuffer = Buffer.concat(args.map(byte => byte.toBuffer()));
      const expectedHash = keccak256(inputBuffer);
      expect(resultBuffer).toEqual(expectedHash);
    });

    it('Should hash correctly - indirect', async () => {
      const args = randomMemoryBytes(10);
      const indirect = new Addressing([
        /*dstOffset=*/ AddressingMode.INDIRECT,
        /*messageOffset*/ AddressingMode.INDIRECT,
        /*messageSizeOffset*/ AddressingMode.INDIRECT,
      ]).toWire();
      const messageOffset = 0;
      const messageOffsetReal = 10;
      const messageSizeOffset = 1;
      const messageSizeOffsetReal = 100;
      const dstOffset = 2;
      const dstOffsetReal = 30;
      context.machineState.memory.set(messageOffset, new Uint32(messageOffsetReal));
      context.machineState.memory.set(dstOffset, new Uint32(dstOffsetReal));
      context.machineState.memory.set(messageSizeOffset, new Uint32(messageSizeOffsetReal));
      context.machineState.memory.set(messageSizeOffsetReal, new Uint32(args.length));
      context.machineState.memory.setSlice(messageOffsetReal, args);

      await new Keccak(indirect, dstOffset, messageOffset, messageSizeOffset).execute(context);

      const resultBuffer = Buffer.concat(
        context.machineState.memory.getSliceAs<Uint8>(dstOffsetReal, 32).map(byte => byte.toBuffer()),
      );
      const inputBuffer = Buffer.concat(args.map(byte => byte.toBuffer()));
      const expectedHash = keccak256(inputBuffer);
      expect(resultBuffer).toEqual(expectedHash);
    });
  });

  describe('Keccakf1600', () => {
    it('Should (de)serialize correctly', () => {
      const buf = Buffer.from([
        KeccakF1600.opcode, // opcode
        1, // indirect
        ...Buffer.from('1234', 'hex'), // dstOffset
        ...Buffer.from('2345', 'hex'), // messageOffset
        ...Buffer.from('3456', 'hex'), // messageSizeOffset
      ]);
      const inst = new KeccakF1600(
        /*indirect=*/ 1,
        /*dstOffset=*/ 0x1234,
        /*messageOffset=*/ 0x2345,
        /*messageSizeOffset=*/ 0x3456,
      );

      expect(KeccakF1600.deserialize(buf)).toEqual(inst);
      expect(inst.serialize()).toEqual(buf);
    });

    it('Should permute correctly - direct', async () => {
      const rawArgs = [...Array(25)].map(_ => 0n);
      const args = rawArgs.map(a => new Uint64(a));
      const indirect = 0;
      const messageOffset = 0;
      const messageSizeOffset = 50;
      const dstOffset = 100;
      context.machineState.memory.set(messageSizeOffset, new Uint32(args.length));
      context.machineState.memory.setSlice(messageOffset, args);

      await new KeccakF1600(indirect, dstOffset, messageOffset, messageSizeOffset).execute(context);

      const result = context.machineState.memory.getSliceAs<Uint64>(dstOffset, 25);
      expect(result).toEqual(keccakf1600(rawArgs).map(a => new Uint64(a)));
    });
  });

  describe('Sha256Compression', () => {
    it('Should (de)serialize correctly', () => {
      const buf = Buffer.from([
        Sha256Compression.opcode, // opcode
        1, // indirect
        ...Buffer.from('1234', 'hex'), // dstOffset
        ...Buffer.from('2345', 'hex'), // stateOffset
        ...Buffer.from('4567', 'hex'), // inputsOffset
      ]);
      const inst = new Sha256Compression(
        /*indirect=*/ 1,
        /*dstOffset=*/ 0x1234,
        /*stateOffset=*/ 0x2345,
        /*inputsOffset=*/ 0x4567,
      );

      expect(Sha256Compression.deserialize(buf)).toEqual(inst);
      expect(inst.serialize()).toEqual(buf);
    });

    it('Should hash correctly - direct', async () => {
      const state = randomMemoryUint32s(8);
      const stateArray = Uint32Array.from(state.map(byte => byte.toNumber()));
      const inputs = randomMemoryUint32s(16);
      const inputsArray = Uint32Array.from(inputs.map(byte => byte.toNumber()));
      const indirect = 0;
      const stateOffset = 0;
      const stateSizeOffset = 100;
      const inputsOffset = 200;
      const inputsSizeOffset = 300;
      const outputOffset = 300;
      context.machineState.memory.set(stateSizeOffset, new Uint32(state.length));
      context.machineState.memory.setSlice(stateOffset, state);
      context.machineState.memory.set(inputsSizeOffset, new Uint32(inputs.length));
      context.machineState.memory.setSlice(inputsOffset, inputs);

      await new Sha256Compression(indirect, outputOffset, stateOffset, inputsOffset).execute(context);

      const output = context.machineState.memory.getSliceAs<Uint32>(outputOffset, 8);
      const outputArray = Uint32Array.from(output.map(word => word.toNumber()));

      const expectedOutput = sha256Compression(stateArray, inputsArray);
      expect(outputArray).toEqual(expectedOutput);
    });

    it('Should hash correctly - indirect', async () => {
      const state = randomMemoryUint32s(8);
      const stateArray = Uint32Array.from(state.map(byte => byte.toNumber()));
      const inputs = randomMemoryUint32s(16);
      const inputsArray = Uint32Array.from(inputs.map(byte => byte.toNumber()));
      const indirect = new Addressing([
        /*dstOffset=*/ AddressingMode.INDIRECT,
        /*stateOffset*/ AddressingMode.INDIRECT,
        /*inputsOffset*/ AddressingMode.INDIRECT,
      ]).toWire();
      const stateOffset = 0;
      const stateOffsetReal = 10;
      const stateSizeOffset = 1;
      const stateSizeOffsetReal = 100;
      const inputsOffset = 2;
      const inputsOffsetReal = 200;
      const inputsSizeOffset = 3;
      const inputsSizeOffsetReal = 300;
      const outputOffset = 4;
      const outputOffsetReal = 400;
      context.machineState.memory.set(stateSizeOffset, new Uint32(stateSizeOffsetReal));
      context.machineState.memory.set(stateSizeOffsetReal, new Uint32(state.length));
      context.machineState.memory.set(stateOffset, new Uint32(stateOffsetReal));
      context.machineState.memory.setSlice(stateOffsetReal, state);
      context.machineState.memory.set(inputsSizeOffset, new Uint32(inputsSizeOffsetReal));
      context.machineState.memory.set(inputsSizeOffsetReal, new Uint32(inputs.length));
      context.machineState.memory.set(inputsOffset, new Uint32(inputsOffsetReal));
      context.machineState.memory.setSlice(inputsOffsetReal, inputs);
      context.machineState.memory.set(outputOffset, new Uint32(outputOffsetReal));

      await new Sha256Compression(indirect, outputOffset, stateOffset, inputsOffset).execute(context);

      const output = context.machineState.memory.getSliceAs<Uint32>(outputOffsetReal, 8);
      const outputArray = Uint32Array.from(output.map(word => word.toNumber()));

      const expectedOutput = sha256Compression(stateArray, inputsArray);
      expect(outputArray).toEqual(expectedOutput);
    });
  });

  describe('Pedersen', () => {
    it('Should (de)serialize correctly', () => {
      const buf = Buffer.from([
        Pedersen.opcode, // opcode
        1, // indirect
        ...Buffer.from('02345678', 'hex'), // genIndexOffset
        ...Buffer.from('12345678', 'hex'), // dstOffset
        ...Buffer.from('23456789', 'hex'), // messageOffset
        ...Buffer.from('3456789a', 'hex'), // hashSize
      ]);
      const inst = new Pedersen(
        /*indirect=*/ 1,
        /*genIndexOffset=*/ 0x02345678,
        /*dstOffset=*/ 0x12345678,
        /*messageOffset=*/ 0x23456789,
        /*hashSizeOffset=*/ 0x3456789a,
      );

      expect(Pedersen.deserialize(buf)).toEqual(inst);
      expect(inst.serialize()).toEqual(buf);
    });

    it('Should hash correctly - direct', async () => {
      const args = randomMemoryFields(10);
      const messageOffset = 0;
      const sizeOffset = 20;
      const genIndexOffset = 30;
      const indirect = 0;
      const genIndex = 20;

      context.machineState.memory.setSlice(messageOffset, args);
      context.machineState.memory.set(sizeOffset, new Uint32(args.length));
      context.machineState.memory.set(genIndexOffset, new Uint32(genIndex));

      const dstOffset = 3;

      const expectedHash = pedersenHash(args, genIndex);
      await new Pedersen(indirect, genIndexOffset, dstOffset, messageOffset, sizeOffset).execute(context);

      const result = context.machineState.memory.get(dstOffset);
      expect(result).toEqual(new Field(expectedHash));
    });

    it('Should hash correctly - indirect', async () => {
      const args = randomMemoryFields(10);
      const indirect = new Addressing([
        /*genIndexOffset=*/ AddressingMode.DIRECT,
        /*dstOffset=*/ AddressingMode.DIRECT,
        /*messageOffset*/ AddressingMode.INDIRECT,
        /*messageSizeOffset*/ AddressingMode.INDIRECT,
      ]).toWire();
      const messageOffset = 0;
      const sizeOffset = 20;
      const realLocation = 4;
      const realSizeLocation = 21;
      const genIndexOffset = 50;

      context.machineState.memory.set(messageOffset, new Uint32(realLocation));
      context.machineState.memory.set(sizeOffset, new Uint32(realSizeLocation));
      context.machineState.memory.setSlice(realLocation, args);
      context.machineState.memory.set(realSizeLocation, new Uint32(args.length));
      context.machineState.memory.set(genIndexOffset, new Uint32(0));

      const dstOffset = 300;

      const expectedHash = pedersenHash(args);
      await new Pedersen(indirect, genIndexOffset, dstOffset, messageOffset, sizeOffset).execute(context);

      const result = context.machineState.memory.get(dstOffset);
      expect(result).toEqual(new Field(expectedHash));
    });
  });
});
