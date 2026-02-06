// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISUSDS} from "../interfaces/ISUSDS.sol";

/// @dev Mock sUSDS contract for testing. Allows setting ssr, chi, rho values.
contract MockSUSDS is ISUSDS {
    uint256 public ssr;
    uint256 public chi;
    uint256 public rho;

    function setSSRData(uint256 ssr_, uint256 chi_, uint256 rho_) external {
        ssr = ssr_;
        chi = chi_;
        rho = rho_;
    }
}
