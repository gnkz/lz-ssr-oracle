// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OApp, Origin, MessagingFee} from "lz-oapp/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "lz-oapp/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ISUSDS} from "./interfaces/ISUSDS.sol";

/// @title SSRForwarder
/// @notice Forwards USDS savings rate data from Mainnet to remote chains via LayerZero
/// @dev This contract reads the current SSR (Savings Rate), chi (rate accumulator), and rho (last update timestamp)
/// from the sUSDS contract and sends them cross-chain to SSROracle instances on destination chains.
///
/// The contract uses LayerZero V2's OApp pattern for cross-chain messaging. Only addresses with the OPERATOR
/// role can trigger forwards, while the owner manages operator permissions and LayerZero configuration.
///
/// This is a send-only OApp; receiving messages is not supported and will revert.
contract SSRForwarder is OApp, OAppOptionsType3, AccessControl {
    /// @notice Role identifier for addresses authorized to call forward()
    bytes32 public constant OPERATOR = keccak256("OPERATOR_ROLE");

    /// @notice Message type identifier for LayerZero options
    /// @dev Used with combineOptions() to merge enforced and user-provided options
    uint16 public constant SEND = 1;

    /// @notice The sUSDS contract to read savings rate data from
    ISUSDS public immutable SUSDS;

    /// @notice Emitted when SSR data is forwarded to a remote chain
    /// @param dstEid The destination chain's LayerZero endpoint ID
    /// @param operator The address that triggered the forward
    /// @param ssr The savings rate per second (RAY precision)
    /// @param chi The rate accumulator (RAY precision)
    /// @param rho The timestamp of the last chi update
    event Forwarded(uint32 indexed dstEid, address indexed operator, uint256 ssr, uint256 chi, uint256 rho);

    /// @notice Emitted when an operator's permissions are modified
    /// @param operator The address whose permissions changed
    /// @param owner The owner who made the change
    /// @param isOperator True if granted operator role, false if revoked
    event OperatorModified(address indexed operator, address indexed owner, bool isOperator);

    /// @notice Thrown when attempting to receive a LayerZero message
    /// @dev This contract is send-only and does not accept incoming messages
    error NotImplemented();

    /// @notice Initializes the forwarder with LayerZero endpoint, owner, and sUSDS contract
    /// @param endpoint_ The LayerZero endpoint address on this chain
    /// @param owner_ The owner address with admin privileges
    /// @param susds_ The sUSDS contract address to read rate data from
    constructor(address endpoint_, address owner_, address susds_) OApp(endpoint_, owner_) Ownable(owner_) {
        SUSDS = ISUSDS(susds_);
    }

    /// @notice Grants or revokes the OPERATOR role for an address
    /// @dev Only callable by the contract owner
    /// @param operator_ The address to modify permissions for
    /// @param isOperator_ True to grant operator role, false to revoke
    function setOperator(address operator_, bool isOperator_) external onlyOwner {
        if (isOperator_) {
            _grantRole(OPERATOR, operator_);
        } else {
            _revokeRole(OPERATOR, operator_);
        }

        emit OperatorModified(operator_, msg.sender, isOperator_);
    }

    /// @notice Estimates the fee required to forward SSR data to a destination chain
    /// @dev Combines enforced options (set by owner) with caller-provided options
    /// @param dstEid_ The destination chain's LayerZero endpoint ID
    /// @param options_ Additional LayerZero options (gas limits, etc.)
    /// @param payInLzToken_ Whether to pay fees in LZ token (true) or native token (false)
    /// @return MessagingFee struct containing nativeFee and lzTokenFee
    function quote(uint32 dstEid_, bytes calldata options_, bool payInLzToken_)
        external
        view
        returns (MessagingFee memory)
    {
        return _quote(dstEid_, _getPayload(), combineOptions(dstEid_, SEND, options_), payInLzToken_);
    }

    /// @notice Forwards current SSR data to a destination chain
    /// @dev Only callable by addresses with OPERATOR role. Requires msg.value to cover LayerZero fees.
    /// Excess fees are refunded to msg.sender.
    /// @param dstEid_ The destination chain's LayerZero endpoint ID
    /// @param options_ LayerZero execution options (gas limits for destination execution)
    function forward(uint32 dstEid_, bytes calldata options_) external payable onlyRole(OPERATOR) {
        _lzSend(dstEid_, _getPayload(), options_, MessagingFee(msg.value, 0), payable(msg.sender));

        emit Forwarded(dstEid_, msg.sender, SUSDS.ssr(), SUSDS.chi(), SUSDS.rho());
    }

    /// @notice Builds the payload containing current SSR data
    /// @dev Reads ssr, chi, and rho from the sUSDS contract and ABI-encodes them
    /// @return ABI-encoded payload of (uint256 ssr, uint256 chi, uint256 rho)
    function _getPayload() internal view returns (bytes memory) {
        uint256 ssr = SUSDS.ssr();
        uint256 chi = SUSDS.chi();
        uint256 rho = SUSDS.rho();

        return abi.encode(ssr, chi, rho);
    }

    /// @notice Handles incoming LayerZero messages (not supported)
    /// @dev Always reverts as this contract only sends messages
    function _lzReceive(Origin calldata, bytes32, bytes calldata, address, bytes calldata) internal override {
        revert NotImplemented();
    }
}
