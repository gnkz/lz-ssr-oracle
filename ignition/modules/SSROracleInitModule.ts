import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import SSROracleModule from "./SSROracleModule.js";

export default buildModule("SSROracleInitModule", (m) => {
  const { oracle, endpoint } = m.useModule(SSROracleModule);

  // Oracle only RECEIVES messages from mainnet, so only configure receive library
  m.call(endpoint, "setReceiveLibrary", [
    oracle,
    m.getParameter("remoteEID"),
    m.getParameter("receiveLib"),
    0n,
  ]);

  // Set receive ULN config (configType 2 only, no executor config for receive)
  const ulnConfigParam = {
    eid: m.getParameter("remoteEID"),
    configType: 2,
    config: m.getParameter("encodedUlnConfig"),
  };

  m.call(
    endpoint,
    "setConfig",
    [oracle, m.getParameter("receiveLib"), [ulnConfigParam]],
    { id: "setReceiveConfig" },
  );

  // Note: Oracle doesn't send, so no enforced options needed

  return { oracle, endpoint };
});
