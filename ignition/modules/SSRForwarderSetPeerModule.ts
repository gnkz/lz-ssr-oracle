import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import SSRForwarderInitModule from "./SSRForwarderInitModule.js";

export default buildModule("SSRForwarderSetPeerModule", (m) => {
  const { forwarder } = m.useModule(SSRForwarderInitModule);

  m.call(forwarder, "setPeer", [
    m.getParameter("remoteEID"),
    m.getParameter("peer"),
  ]);

  return { forwarder };
});
