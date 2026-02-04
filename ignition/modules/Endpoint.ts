import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("EndpointModule", (m) => {
  const endpointAddr = m.getParameter("endpoint");

  const endpoint = m.contractAt("ILayerZeroEndpointV2", endpointAddr);

  return { endpoint };
});
