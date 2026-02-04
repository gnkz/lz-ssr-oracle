import hre from "hardhat";
import { Address, getAddress, padHex } from "viem";
import {
  encodeExecutorConfig,
  encodeOptions,
  encodeUlnConfig,
} from "./utils.js";
import SSRForwarderInitModule from "../ignition/modules/SSRForwarderInitModule.js";
import SSRForwarderSetPeerModule from "../ignition/modules/SSRForwarderSetPeerModule.js";
import SSROracleInitModule from "../ignition/modules/SSROracleInitModule.js";
import SSROracleSetPeerModule from "../ignition/modules/SSROracleSetPeerModule.js";

// LayerZero Endpoint IDs
const EID = {
  MAINNET: 30101,
  PLASMA: 30383,
} as const;

// Shared owner across both chains
const OWNER = getAddress("0xAEa0C070062fd244E1a3098E405ACFadFbe1411B");

// ULN Config: 15 confirmations, 2 required DVNs
const ULN_CONFIRMATIONS = 15n;
const REQUIRED_DVNS = 2;

// Executor config
const EXECUTOR_MAX_MESSAGE_SIZE = 10_000;
const LZ_RECEIVE_GAS = 100_000n;

const mainnetConfig = {
  endpoint: getAddress("0x1a44076050125825900e736c501f859c50fE728c"),
  usds: getAddress("0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD"),
  executor: getAddress("0x173272739Bd7Aa6e4e214714048a9fE699453059"),
  sendLib: getAddress("0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1"),
  receiveLib: getAddress("0xc02Ab410f0734EFa3F14628780e6e695156024C2"),
  dvns: [
    getAddress("0x589dedbd617e0cbcb916a9223f4d1300c294236b"), // LZ Labs
    getAddress("0xa59ba433ac34d2927232918ef5b2eaafcf130ba5"), // Nethermind
  ] as Address[],
};

const plasmaConfig = {
  endpoint: getAddress("0x6F475642a6e85809B1c36Fa62763669b1b48DD5B"),
  receiveLib: getAddress("0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043"),
  dvns: [
    getAddress("0x282b3386571f7f794450d5789911a9804FA346b4"), // LZ Labs
    getAddress("0xa51cE237FaFA3052D5d3308Df38A024724Bb1274"), // Nethermind
  ] as Address[],
};

function getMainnetParameters() {
  const encodedUlnConfig = encodeUlnConfig(
    ULN_CONFIRMATIONS,
    REQUIRED_DVNS,
    0,
    0,
    mainnetConfig.dvns,
    [],
  );

  return {
    EndpointModule: { endpoint: mainnetConfig.endpoint },
    SSRForwarderModule: { owner: OWNER, usds: mainnetConfig.usds },
    SSRForwarderInitModule: {
      remoteEID: EID.PLASMA,
      executor: mainnetConfig.executor,
      sendLib: mainnetConfig.sendLib,
      receiveLib: mainnetConfig.receiveLib,
      encodedUlnConfig,
      encodedExecConfig: encodeExecutorConfig(
        EXECUTOR_MAX_MESSAGE_SIZE,
        mainnetConfig.executor,
      ),
      encodedReceiveOptions: encodeOptions(3, 1, 1, LZ_RECEIVE_GAS, 0n),
      owner: OWNER,
    },
  };
}

function getPlasmaParameters() {
  const encodedUlnConfig = encodeUlnConfig(
    ULN_CONFIRMATIONS,
    REQUIRED_DVNS,
    0,
    0,
    plasmaConfig.dvns,
    [],
  );

  return {
    EndpointModule: { endpoint: plasmaConfig.endpoint },
    SSROracleModule: { owner: OWNER },
    SSROracleInitModule: {
      remoteEID: EID.MAINNET,
      receiveLib: plasmaConfig.receiveLib,
      encodedUlnConfig,
    },
  };
}

async function main() {
  const mainnetConn = await hre.network.connect("mainnet");
  const plasmaConn = await hre.network.connect("plasma");

  // Deploy contracts
  const { forwarder } = await mainnetConn.ignition.deploy(
    SSRForwarderInitModule,
    { parameters: getMainnetParameters() },
  );

  const { oracle } = await plasmaConn.ignition.deploy(SSROracleInitModule, {
    parameters: getPlasmaParameters(),
  });

  // Set peers on both chains
  await plasmaConn.ignition.deploy(SSROracleSetPeerModule, {
    parameters: {
      ...getPlasmaParameters(),
      SSROracleSetPeerModule: {
        remoteEID: EID.MAINNET,
        peer: padHex(forwarder.address),
      },
    },
  });

  await mainnetConn.ignition.deploy(SSRForwarderSetPeerModule, {
    parameters: {
      ...getMainnetParameters(),
      SSRForwarderSetPeerModule: {
        remoteEID: EID.PLASMA,
        peer: padHex(oracle.address),
      },
    },
  });

  // Forward SSR to Plasma
  const options = encodeOptions(3, 1, 1, LZ_RECEIVE_GAS, 0n);
  const fee = await forwarder.read.quote([EID.PLASMA, options, false]);
  const hash = await forwarder.write.forward([EID.PLASMA, options], {
    value: fee.nativeFee,
  });

  console.log(hash.toString());
}

main().catch(console.error);
