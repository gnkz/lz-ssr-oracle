import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    npmFilesToBuild: [
      "lz-protocol/contracts/interfaces/ILayerZeroEndpointV2.sol",
    ],
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    plasma: {
      type: "http",
      chainType: "l1",
      url: configVariable("PLASMA_RPC_URL"),
      accounts: [configVariable("PRIVATE_KEY")],
    },
    base: {
      type: "http",
      chainType: "op",
      url: configVariable("BASE_RPC_URL"),
      accounts: [configVariable("PRIVATE_KEY")],
    },
    mainnet: {
      type: "http",
      chainType: "op",
      url: configVariable("MAINNET_RPC_URL"),
      accounts: [configVariable("PRIVATE_KEY")],
    },
  },
});
