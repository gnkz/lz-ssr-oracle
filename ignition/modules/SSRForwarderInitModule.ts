import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import SSRForwarderModule from "./SSRForwarderModule.js";

export default buildModule("SSRForwarderInitModule", (m) => {
  const { forwarder, endpoint } = m.useModule(SSRForwarderModule);

  m.call(endpoint, "setSendLibrary", [
    forwarder,
    m.getParameter("remoteEID"),
    m.getParameter("sendLib"),
  ]);

  m.call(endpoint, "setReceiveLibrary", [
    forwarder,
    m.getParameter("remoteEID"),
    m.getParameter("receiveLib"),
    0n,
  ]);

  const execConfigParam = {
    eid: m.getParameter("remoteEID"),
    configType: 1,
    config: m.getParameter("encodedExecConfig"),
  };

  const ulnConfigParam = {
    eid: m.getParameter("remoteEID"),
    configType: 2,
    config: m.getParameter("encodedUlnConfig"),
  };

  m.call(
    endpoint,
    "setConfig",
    [forwarder, m.getParameter("sendLib"), [execConfigParam, ulnConfigParam]],
    { id: "setSendConfig" },
  );

  // Set enforced options only for the remote EID (Plasma)
  m.call(forwarder, "setEnforcedOptions", [
    [
      {
        eid: m.getParameter("remoteEID"),
        msgType: 1,
        options: m.getParameter("encodedReceiveOptions"),
      },
    ],
  ]);

  m.call(forwarder, "setOperator", [m.getParameter("owner"), true]);

  return { forwarder, endpoint };
});
