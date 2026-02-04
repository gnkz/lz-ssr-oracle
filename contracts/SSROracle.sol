// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OApp, Origin, MessagingFee} from "lz-oapp/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "lz-oapp/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SSROracle
/// @notice Receives and stores USDS savings rate data from Mainnet via LayerZero
/// @dev This contract acts as an oracle for the USDS savings rate on remote chains.
/// It receives SSR data (ssr, chi, rho) from SSRForwarder on Mainnet and provides
/// a `getConversionRate()` function that calculates the current conversion rate
/// by compounding the interest since the last update.
///
/// The conversion rate represents how many USDS tokens one sUSDS share is worth,
/// accounting for accrued interest. This enables DApps on this chain to accurately
/// price sUSDS without direct access to Mainnet state.
///
/// This is a receive-only OApp; it does not send cross-chain messages.
contract SSROracle is OApp, OAppOptionsType3 {
    /// @notice Packed struct storing the savings rate parameters
    /// @dev Packed into a single 256-bit storage slot for gas efficiency:
    /// - ssr (96 bits): Sufficient for RAY-based rates (max ~7.9e28)
    /// - chi (120 bits): Sufficient for accumulated rates over decades
    /// - rho (40 bits): Unix timestamp, sufficient until year 36812
    struct SSRData {
        uint96 ssr;
        uint120 chi;
        uint40 rho;
    }

    /// @notice The RAY unit (1e27) used for fixed-point arithmetic
    /// @dev All rate calculations use RAY precision following Maker DSS conventions
    uint256 public constant RAY = 1e27;

    /// @notice The current savings rate data received from Mainnet
    /// @dev Updated via LayerZero messages from SSRForwarder
    SSRData public ssrData;

    /// @notice Emitted when new SSR data is received and stored
    /// @param oldSsr Previous savings rate
    /// @param newSsr New savings rate
    /// @param oldChi Previous rate accumulator
    /// @param newChi New rate accumulator
    /// @param oldRho Previous update timestamp
    /// @param newRho New update timestamp
    event SSRDataUpdated(
        uint256 oldSsr, uint256 newSsr, uint256 oldChi, uint256 newChi, uint256 oldRho, uint256 newRho
    );

    /// @notice Thrown when received data has an older timestamp than stored data
    /// @dev Prevents replay attacks and out-of-order message delivery
    error StaleData();

    /// @notice Initializes the oracle with LayerZero endpoint and owner
    /// @param endpoint_ The LayerZero endpoint address on this chain
    /// @param owner_ The owner address with admin privileges for LayerZero configuration
    constructor(address endpoint_, address owner_) OApp(endpoint_, owner_) Ownable(owner_) {}

    /// @notice Calculates the current sUSDS to USDS conversion rate
    /// @dev Compounds interest from the last update (rho) to the current block timestamp.
    /// Formula: chi * ssr^(block.timestamp - rho) / RAY
    ///
    /// The result represents how many USDS tokens one sUSDS share is currently worth.
    /// For example, a return value of 1.05e27 means 1 sUSDS = 1.05 USDS.
    ///
    /// @return The current conversion rate in RAY precision (1e27 = 1:1)
    function getConversionRate() external view returns (uint256) {
        uint256 timeDelta = block.timestamp - ssrData.rho;

        return uint256(ssrData.chi) * _rpow(uint256(ssrData.ssr), timeDelta) / RAY;
    }

    /// @notice Computes x^n in RAY precision using binary exponentiation
    /// @dev Implements the same algorithm as Maker's DSS rpow function.
    /// Uses iterative squaring for O(log n) complexity.
    /// @param x_ The base in RAY (1e27 = 1.0)
    /// @param n_ The exponent (typically seconds elapsed)
    /// @return z The result x^n in RAY precision
    function _rpow(uint256 x_, uint256 n_) internal pure returns (uint256 z) {
        z = n_ % 2 != 0 ? x_ : RAY;
        for (n_ /= 2; n_ != 0; n_ /= 2) {
            x_ = x_ * x_ / RAY;
            if (n_ % 2 != 0) {
                z = z * x_ / RAY;
            }
        }
    }

    /// @notice Handles incoming LayerZero messages containing SSR data
    /// @dev Decodes the payload as (ssr, chi, rho) and updates storage.
    /// Reverts if the incoming rho is older than the stored rho to prevent stale updates.
    /// @param payload_ ABI-encoded (uint256 ssr, uint256 chi, uint256 rho)
    function _lzReceive(Origin calldata, bytes32, bytes calldata payload_, address, bytes calldata) internal override {
        (uint256 ssr, uint256 chi, uint256 rho) = abi.decode(payload_, (uint256, uint256, uint256));

        SSRData memory data = ssrData;

        if (data.rho > rho) {
            revert StaleData();
        }

        ssrData = SSRData(uint96(ssr), uint120(chi), uint40(rho));

        emit SSRDataUpdated(data.ssr, ssr, data.chi, chi, data.rho, rho);
    }
}
