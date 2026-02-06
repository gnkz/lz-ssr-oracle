// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingFee,
    MessagingReceipt,
    Origin
} from "lz-protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "lz-protocol/contracts/interfaces/IMessageLibManager.sol";

/// @dev Minimal mock of the LayerZero V2 endpoint for unit testing OApp contracts.
/// Only implements the functions that OAppCore/OAppSender/OAppReceiver actually call.
contract MockLZEndpoint is ILayerZeroEndpointV2 {
    uint32 public eid;

    uint256 public nativeFee;
    uint64 public nextNonce;

    /// @dev Last send() call data, for assertions.
    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    bytes public lastMessage;
    bytes public lastOptions;
    address public lastRefundAddress;

    constructor(uint32 eid_) {
        eid = eid_;
        nativeFee = 0.01 ether;
        nextNonce = 1;
    }

    function setNativeFee(uint256 fee_) external {
        nativeFee = fee_;
    }

    // ──────────── ILayerZeroEndpointV2 core ────────────

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory) {
        return MessagingFee(nativeFee, 0);
    }

    error InsufficientFee(uint256 required, uint256 provided);

    function send(MessagingParams calldata params_, address refundAddress_)
        external
        payable
        returns (MessagingReceipt memory)
    {
        if (msg.value < nativeFee) revert InsufficientFee(nativeFee, msg.value);

        lastDstEid = params_.dstEid;
        lastReceiver = params_.receiver;
        lastMessage = params_.message;
        lastOptions = params_.options;
        lastRefundAddress = refundAddress_;

        bytes32 guid = keccak256(abi.encodePacked(nextNonce, params_.dstEid, params_.receiver));
        MessagingReceipt memory receipt = MessagingReceipt(guid, nextNonce, MessagingFee(msg.value, 0));
        nextNonce++;

        // Refund excess native
        uint256 excess = msg.value - nativeFee;
        if (excess > 0) {
            (bool ok,) = refundAddress_.call{value: excess}("");
            require(ok, "refund failed");
        }

        return receipt;
    }

    function verify(Origin calldata, address, bytes32) external {}

    function verifiable(Origin calldata, address) external pure returns (bool) {
        return true;
    }

    function initializable(Origin calldata, address) external pure returns (bool) {
        return true;
    }

    function lzReceive(Origin calldata origin_, address receiver_, bytes32 guid_, bytes calldata message_, bytes calldata extraData_)
        external
        payable
    {
        // Simulate the endpoint calling lzReceive on the receiver
        ILayerZeroEndpointV2(receiver_).lzReceive(origin_, receiver_, guid_, message_, extraData_);
    }

    function clear(address, Origin calldata, bytes32, bytes calldata) external {}

    function setLzToken(address) external {}

    function lzToken() external pure returns (address) {
        return address(0);
    }

    function nativeToken() external pure returns (address) {
        return address(0);
    }

    function setDelegate(address) external {}

    // ──────────── IMessagingChannel ────────────

    function skip(address, uint32, bytes32, uint64) external {}

    function nilify(address, uint32, bytes32, uint64, bytes32) external {}

    function burn(address, uint32, bytes32, uint64, bytes32) external {}

    function nextGuid(address, uint32, bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function inboundNonce(address, uint32, bytes32) external pure returns (uint64) {
        return 0;
    }

    function outboundNonce(address, uint32, bytes32) external pure returns (uint64) {
        return 0;
    }

    function inboundPayloadHash(address, uint32, bytes32, uint64) external pure returns (bytes32) {
        return bytes32(0);
    }

    function lazyInboundNonce(address, uint32, bytes32) external pure returns (uint64) {
        return 0;
    }

    // ──────────── IMessagingComposer ────────────

    function composeQueue(address, address, bytes32, uint16) external pure returns (bytes32) {
        return bytes32(0);
    }

    function sendCompose(address, bytes32, uint16, bytes calldata) external {}

    function lzCompose(address, address, bytes32, uint16, bytes calldata, bytes calldata) external payable {}

    // ──────────── IMessagingContext ────────────

    function isSendingMessage() external pure returns (bool) {
        return false;
    }

    function getSendContext() external pure returns (uint32, address) {
        return (0, address(0));
    }

    // ──────────── IMessageLibManager ────────────

    function registerLibrary(address) external {}

    function isRegisteredLibrary(address) external pure returns (bool) {
        return true;
    }

    function getRegisteredLibraries() external pure returns (address[] memory) {
        return new address[](0);
    }

    function setDefaultSendLibrary(uint32, address) external {}

    function defaultSendLibrary(uint32) external pure returns (address) {
        return address(0);
    }

    function setDefaultReceiveLibrary(uint32, address, uint256) external {}

    function defaultReceiveLibrary(uint32) external pure returns (address) {
        return address(0);
    }

    function setDefaultReceiveLibraryTimeout(uint32, address, uint256) external {}

    function defaultReceiveLibraryTimeout(uint32) external pure returns (address, uint256) {
        return (address(0), 0);
    }

    function isSupportedEid(uint32) external pure returns (bool) {
        return true;
    }

    function isValidReceiveLibrary(address, uint32, address) external pure returns (bool) {
        return true;
    }

    function setSendLibrary(address, uint32, address) external {}

    function getSendLibrary(address, uint32) external pure returns (address) {
        return address(0);
    }

    function isDefaultSendLibrary(address, uint32) external pure returns (bool) {
        return true;
    }

    function setReceiveLibrary(address, uint32, address, uint256) external {}

    function getReceiveLibrary(address, uint32) external pure returns (address, bool) {
        return (address(0), true);
    }

    function setReceiveLibraryTimeout(address, uint32, address, uint256) external {}

    function receiveLibraryTimeout(address, uint32) external pure returns (address, uint256) {
        return (address(0), 0);
    }

    function setConfig(address, address, SetConfigParam[] calldata) external {}

    function getConfig(address, address, uint32, uint32) external pure returns (bytes memory) {
        return "";
    }
}
