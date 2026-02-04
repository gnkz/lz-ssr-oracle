import {
  encodeAbiParameters,
  Address,
  size,
  toBytes,
  encodePacked,
} from "viem";

export function encodeUlnConfig(
  confirmations: bigint,
  requiredDVNCount: number,
  optionalDVNCount: number,
  optionalDVNThreshold: number,
  requiredDVNs: Address[],
  optionalDVNs: Address[],
): `0x${string}` {
  return encodeAbiParameters(
    [
      {
        type: "tuple",
        components: [
          { name: "confirmations", type: "uint64" },
          { name: "requiredDVNCount", type: "uint8" },
          { name: "optionalDVNCount", type: "uint8" },
          { name: "optionalDVNThreshold", type: "uint8" },
          { name: "requiredDVNs", type: "address[]" },
          { name: "optionalDVNs", type: "address[]" },
        ],
      },
    ],
    [
      {
        confirmations,
        requiredDVNCount,
        optionalDVNCount,
        optionalDVNThreshold,
        requiredDVNs,
        optionalDVNs,
      },
    ],
  );
}

export function encodeExecutorConfig(
  maxMessageSize: number,
  executor: Address,
): `0x${string}` {
  return encodeAbiParameters(
    [
      {
        type: "tuple",
        components: [
          { name: "maxMessageSize", type: "uint32" },
          { name: "executor", type: "address" },
        ],
      },
    ],
    [{ maxMessageSize, executor }],
  );
}

export function encodeOptions(
  optionsHeader: number,
  optionType: number,
  workerId: number,
  gas: bigint,
  value: bigint,
): `0x${string}` {
  const encodedOptionsHeader = encodePacked(["uint16"], [optionsHeader]);

  const encodedOption =
    value === 0n
      ? encodePacked(["uint128"], [gas])
      : encodePacked(["uint128", "uint128"], [gas, value]);

  const optionByteLength = size(toBytes(encodedOption));

  return encodePacked(
    ["bytes", "uint8", "uint16", "uint8", "bytes"],
    [
      encodedOptionsHeader,
      workerId,
      optionByteLength + 1,
      optionType,
      encodedOption,
    ],
  );
}
