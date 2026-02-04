import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import EndpointModule from "./Endpoint.js";

export default buildModule("SSROracleModule", (m) => {
  const { endpoint } = m.useModule(EndpointModule);

  const oracle = m.contract("SSROracle", [endpoint, m.getParameter("owner")]);

  return { oracle, endpoint };
});
