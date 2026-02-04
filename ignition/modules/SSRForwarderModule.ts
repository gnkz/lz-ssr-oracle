import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import EndpointModule from "./Endpoint.js";

export default buildModule("SSRForwarderModule", (m) => {
  const { endpoint } = m.useModule(EndpointModule);

  const forwarder = m.contract("SSRForwarder", [
    endpoint,
    m.getParameter("owner"),
    m.getParameter("usds"),
  ]);

  return { forwarder, endpoint };
});
