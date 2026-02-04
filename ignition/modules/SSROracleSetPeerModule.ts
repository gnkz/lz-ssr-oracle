import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import SSROracleInitModule from "./SSROracleInitModule.js";

export default buildModule("SSROracleSetPeerModule", (m) => {
  const { oracle } = m.useModule(SSROracleInitModule);

  m.call(oracle, "setPeer", [
    m.getParameter("remoteEID"),
    m.getParameter("peer"),
  ]);

  return { oracle };
});
