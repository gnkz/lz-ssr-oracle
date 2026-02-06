// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {SSRForwarder} from "../contracts/SSRForwarder.sol";
import {MockSUSDS} from "../contracts/mocks/MockSUSDS.sol";
import {MockLZEndpoint} from "../contracts/mocks/MockLZEndpoint.sol";
import {Origin, MessagingFee} from "lz-protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SSRForwarderTest is Test {
    SSRForwarder public forwarder;
    MockSUSDS public susds;
    MockLZEndpoint public endpoint;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public stranger = makeAddr("stranger");

    uint32 public constant DST_EID = 30383; // Plasma
    uint32 public constant SRC_EID = 30101; // Mainnet

    // ~5% APY per-second rate in RAY
    uint256 public constant SSR = 1000000001547125957863212448;
    uint256 public constant CHI = 1050000000000000000000000000; // 1.05 RAY
    uint256 public constant RHO = 1700000000;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function setUp() public {
        susds = new MockSUSDS();
        susds.setSSRData(SSR, CHI, RHO);

        endpoint = new MockLZEndpoint(SRC_EID);

        vm.prank(owner);
        forwarder = new SSRForwarder(address(endpoint), owner, address(susds));

        // Set peer so _getPeerOrRevert doesn't fail
        vm.prank(owner);
        forwarder.setPeer(DST_EID, bytes32(uint256(uint160(makeAddr("remoteOracle")))));

        // Grant operator role
        vm.prank(owner);
        forwarder.setOperator(operator, true);
    }

    // ═══════════════════════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════════════════════

    function test_constructor_setsSUSDS() public view {
        assertEq(address(forwarder.SUSDS()), address(susds));
    }

    function test_constructor_setsEndpoint() public view {
        assertEq(address(forwarder.endpoint()), address(endpoint));
    }

    function test_constructor_setsOwner() public view {
        assertEq(forwarder.owner(), owner);
    }

    // ═══════════════════════════════════════════════════════
    //  Constants
    // ═══════════════════════════════════════════════════════

    function test_OPERATOR_role_constant() public view {
        assertEq(forwarder.OPERATOR(), OPERATOR_ROLE);
    }

    function test_SEND_constant() public view {
        assertEq(forwarder.SEND(), 1);
    }

    // ═══════════════════════════════════════════════════════
    //  setOperator
    // ═══════════════════════════════════════════════════════

    function test_setOperator_grantsRole() public {
        address newOp = makeAddr("newOp");

        vm.prank(owner);
        forwarder.setOperator(newOp, true);

        assertTrue(forwarder.hasRole(OPERATOR_ROLE, newOp));
    }

    function test_setOperator_revokesRole() public {
        vm.prank(owner);
        forwarder.setOperator(operator, false);

        assertFalse(forwarder.hasRole(OPERATOR_ROLE, operator));
    }

    function test_setOperator_emitsOperatorModified_onGrant() public {
        address newOp = makeAddr("newOp");

        vm.expectEmit(true, true, false, true);
        emit SSRForwarder.OperatorModified(newOp, owner, true);

        vm.prank(owner);
        forwarder.setOperator(newOp, true);
    }

    function test_setOperator_emitsOperatorModified_onRevoke() public {
        vm.expectEmit(true, true, false, true);
        emit SSRForwarder.OperatorModified(operator, owner, false);

        vm.prank(owner);
        forwarder.setOperator(operator, false);
    }

    function test_setOperator_revertsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        forwarder.setOperator(stranger, true);
    }

    function test_setOperator_operatorCannotGrantRole() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        vm.prank(operator);
        forwarder.setOperator(stranger, true);
    }

    // ═══════════════════════════════════════════════════════
    //  quote
    // ═══════════════════════════════════════════════════════

    function test_quote_returnsEndpointFee() public view {
        MessagingFee memory fee = forwarder.quote(DST_EID, "", false);
        assertEq(fee.nativeFee, endpoint.nativeFee());
        assertEq(fee.lzTokenFee, 0);
    }

    function test_quote_reflectsUpdatedFee() public {
        endpoint.setNativeFee(0.05 ether);

        MessagingFee memory fee = forwarder.quote(DST_EID, "", false);
        assertEq(fee.nativeFee, 0.05 ether);
    }

    function test_quote_revertsIfNoPeer() public {
        uint32 unknownEid = 99999;
        vm.expectRevert();
        forwarder.quote(unknownEid, "", false);
    }

    // ═══════════════════════════════════════════════════════
    //  forward
    // ═══════════════════════════════════════════════════════

    function test_forward_sendsPayloadToEndpoint() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        // Verify the message was sent to the endpoint
        assertEq(endpoint.lastDstEid(), DST_EID);

        // Verify the payload encodes ssr, chi, rho
        bytes memory expectedPayload = abi.encode(SSR, CHI, RHO);
        assertEq(endpoint.lastMessage(), expectedPayload);
    }

    function test_forward_emitsForwardedEvent() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.expectEmit(true, true, false, true);
        emit SSRForwarder.Forwarded(DST_EID, operator, SSR, CHI, RHO);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");
    }

    function test_forward_refundsExcessNative() public {
        uint256 fee = endpoint.nativeFee();
        uint256 excess = 0.05 ether;
        vm.deal(operator, fee + excess);

        uint256 balanceBefore = operator.balance;

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        // Operator should have gotten the non-sent excess back (sent exactly fee, no excess from endpoint perspective)
        assertEq(operator.balance, balanceBefore - fee);
    }

    function test_forward_revertsIfNotOperator() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(stranger, fee);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, OPERATOR_ROLE)
        );
        vm.prank(stranger);
        forwarder.forward{value: fee}(DST_EID, "");
    }

    function test_forward_revertsIfOwnerWithoutOperatorRole() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(owner, fee);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, owner, OPERATOR_ROLE)
        );
        vm.prank(owner);
        forwarder.forward{value: fee}(DST_EID, "");
    }

    function test_forward_revertsIfInsufficientFee() public {
        // The endpoint requires nativeFee (0.01 ether). Sending less should revert
        // at the endpoint's send() level.
        uint256 fee = endpoint.nativeFee();
        uint256 insufficient = fee / 2;
        vm.deal(operator, insufficient);

        vm.expectRevert(
            abi.encodeWithSelector(MockLZEndpoint.InsufficientFee.selector, fee, insufficient)
        );
        vm.prank(operator);
        forwarder.forward{value: insufficient}(DST_EID, "");
    }

    function test_forward_revertsIfNoPeer() public {
        uint32 unknownEid = 99999;
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.expectRevert();
        vm.prank(operator);
        forwarder.forward{value: fee}(unknownEid, "");
    }

    function test_forward_usesCurrentSSRData() public {
        // Update the mock with new values
        uint256 newSsr = 1000000002000000000000000000;
        uint256 newChi = 1100000000000000000000000000;
        uint256 newRho = 1700000100;
        susds.setSSRData(newSsr, newChi, newRho);

        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.expectEmit(true, true, false, true);
        emit SSRForwarder.Forwarded(DST_EID, operator, newSsr, newChi, newRho);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        bytes memory expectedPayload = abi.encode(newSsr, newChi, newRho);
        assertEq(endpoint.lastMessage(), expectedPayload);
    }

    function test_forward_multipleCallsIncrementNonce() public {
        uint256 fee = endpoint.nativeFee();

        vm.deal(operator, fee * 3);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");
        assertEq(endpoint.nextNonce(), 2);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");
        assertEq(endpoint.nextNonce(), 3);
    }

    function test_forward_setsRefundAddressToMsgSender() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        assertEq(endpoint.lastRefundAddress(), operator);
    }

    function test_forward_afterOperatorRevoked() public {
        vm.prank(owner);
        forwarder.setOperator(operator, false);

        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, OPERATOR_ROLE)
        );
        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");
    }

    // ═══════════════════════════════════════════════════════
    //  _lzReceive (always reverts)
    // ═══════════════════════════════════════════════════════

    function test_lzReceive_alwaysReverts() public {
        // OAppReceiver.lzReceive checks: (1) caller is endpoint, (2) origin.sender matches peer.
        // We must satisfy both checks so the call reaches _lzReceive, which should revert.
        bytes32 peer = forwarder.peers(DST_EID);
        Origin memory origin = Origin({srcEid: DST_EID, sender: peer, nonce: 1});

        vm.expectRevert(SSRForwarder.NotImplemented.selector);
        vm.prank(address(endpoint));
        forwarder.lzReceive(origin, bytes32(0), "", address(0), "");
    }

    function test_lzReceive_revertsIfNotEndpoint() public {
        bytes32 peer = forwarder.peers(DST_EID);
        Origin memory origin = Origin({srcEid: DST_EID, sender: peer, nonce: 1});

        vm.expectRevert();
        vm.prank(stranger);
        forwarder.lzReceive(origin, bytes32(0), "", address(0), "");
    }

    function test_lzReceive_revertsIfUnknownPeer() public {
        Origin memory origin = Origin({srcEid: DST_EID, sender: bytes32(uint256(0xbad)), nonce: 1});

        vm.expectRevert();
        vm.prank(address(endpoint));
        forwarder.lzReceive(origin, bytes32(0), "", address(0), "");
    }

    // ═══════════════════════════════════════════════════════
    //  Ownership
    // ═══════════════════════════════════════════════════════

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        forwarder.transferOwnership(newOwner);

        assertEq(forwarder.owner(), newOwner);
    }

    function test_transferOwnership_revertsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        forwarder.transferOwnership(stranger);
    }

    // ═══════════════════════════════════════════════════════
    //  Peer management (inherited from OAppCore)
    // ═══════════════════════════════════════════════════════

    function test_setPeer_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        forwarder.setPeer(DST_EID, bytes32(uint256(1)));
    }

    function test_setPeer_updatesPeer() public {
        bytes32 newPeer = bytes32(uint256(0xdead));

        vm.prank(owner);
        forwarder.setPeer(DST_EID, newPeer);

        assertEq(forwarder.peers(DST_EID), newPeer);
    }

    function test_setPeer_canRemovePeer() public {
        vm.prank(owner);
        forwarder.setPeer(DST_EID, bytes32(0));

        assertEq(forwarder.peers(DST_EID), bytes32(0));
    }

    // ═══════════════════════════════════════════════════════
    //  Payload encoding
    // ═══════════════════════════════════════════════════════

    function test_payload_encodedAsThreeUint256() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        bytes memory payload = endpoint.lastMessage();
        (uint256 decodedSsr, uint256 decodedChi, uint256 decodedRho) =
            abi.decode(payload, (uint256, uint256, uint256));

        assertEq(decodedSsr, SSR);
        assertEq(decodedChi, CHI);
        assertEq(decodedRho, RHO);
    }

    // ═══════════════════════════════════════════════════════
    //  AccessControl interface
    // ═══════════════════════════════════════════════════════

    function test_hasRole_operator() public view {
        assertTrue(forwarder.hasRole(OPERATOR_ROLE, operator));
        assertFalse(forwarder.hasRole(OPERATOR_ROLE, stranger));
    }

    function test_multipleOperators() public {
        address op2 = makeAddr("op2");

        vm.prank(owner);
        forwarder.setOperator(op2, true);

        assertTrue(forwarder.hasRole(OPERATOR_ROLE, operator));
        assertTrue(forwarder.hasRole(OPERATOR_ROLE, op2));

        // Both can forward
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);
        vm.deal(op2, fee);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        vm.prank(op2);
        forwarder.forward{value: fee}(DST_EID, "");
    }

    // ═══════════════════════════════════════════════════════
    //  Edge cases
    // ═══════════════════════════════════════════════════════

    function test_forward_withZeroFeeEndpoint() public {
        endpoint.setNativeFee(0);

        vm.prank(operator);
        forwarder.forward{value: 0}(DST_EID, "");

        // Should succeed with zero fee
        assertEq(endpoint.lastDstEid(), DST_EID);
    }

    function test_forward_toDifferentDestinations() public {
        uint32 dstEid2 = 30110;
        bytes32 peer2 = bytes32(uint256(uint160(makeAddr("remotePeer2"))));

        vm.prank(owner);
        forwarder.setPeer(dstEid2, peer2);

        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee * 2);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");
        assertEq(endpoint.lastDstEid(), DST_EID);

        vm.prank(operator);
        forwarder.forward{value: fee}(dstEid2, "");
        assertEq(endpoint.lastDstEid(), dstEid2);
    }
}
