// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISUSDS
/// @notice Interface for the sUSDS (Savings USDS) vault contract
/// @dev Exposes the interest rate parameters used by the USDS savings module.
/// These values follow the Maker DSS (Dai Savings Rate) pattern with RAY precision (1e27).
interface ISUSDS {
    /// @notice Returns the per-second savings rate
    /// @dev Expressed as a RAY-based rate (1e27 = 1.0 = 0% interest).
    /// For example, 1000000001547125957863212448 ≈ 5% APY
    /// @return The current savings rate per second in RAY
    function ssr() external view returns (uint256);

    /// @notice Returns the rate accumulator (accrued interest multiplier)
    /// @dev chi = chi * ssr^(now - rho) / RAY after each drip.
    /// Represents the cumulative interest multiplier since deployment.
    /// @return The current rate accumulator in RAY
    function chi() external view returns (uint256);

    /// @notice Returns the timestamp of the last rate accumulator update
    /// @dev Used to calculate elapsed time for interest accrual
    /// @return Unix timestamp of the last chi update
    function rho() external view returns (uint256);
}
