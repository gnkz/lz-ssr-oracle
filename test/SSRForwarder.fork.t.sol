// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {SSRForwarder} from "../contracts/SSRForwarder.sol";
import {ISUSDS} from "../contracts/interfaces/ISUSDS.sol";
import {MockLZEndpoint} from "../contracts/mocks/MockLZEndpoint.sol";
import {MessagingFee} from "lz-protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @notice Fork-based integration tests for SSRForwarder against the real sUSDS contract on mainnet
contract SSRForwarderForkTest is Test {
    SSRForwarder public forwarder;
    MockLZEndpoint public endpoint;
    ISUSDS public susds;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");

    uint32 public constant DST_EID = 30383; // Plasma
    uint32 public constant SRC_EID = 30101; // Mainnet

    address public constant SUSDS_MAINNET = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    uint256 public constant RAY = 1e27;

    function setUp() public {
        vm.createSelectFork("mainnet", 24_397_070);

        susds = ISUSDS(SUSDS_MAINNET);
        endpoint = new MockLZEndpoint(SRC_EID);

        vm.prank(owner);
        forwarder = new SSRForwarder(address(endpoint), owner, SUSDS_MAINNET);

        vm.prank(owner);
        forwarder.setPeer(DST_EID, bytes32(uint256(uint160(makeAddr("remoteOracle")))));

        vm.prank(owner);
        forwarder.setOperator(operator, true);
    }

    function test_fork_readsRealSSRData() public {
        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        bytes memory payload = endpoint.lastMessage();
        (uint256 ssr, uint256 chi, uint256 rho) = abi.decode(payload, (uint256, uint256, uint256));

        assertEq(ssr, 1000000001243680656318820312, "ssr should equal value at block");
        assertEq(chi, 1085599589085496159450618781, "chi should equal value at block");
        assertEq(rho, 1770372311, "rho should equal value at block");
    }

    function test_fork_ssrIsPositiveRate() public view {
        uint256 ssr = susds.ssr();
        assertGt(ssr, RAY, "ssr should be > RAY (positive savings rate)");
    }

    function test_fork_chiIsAtLeastRAY() public view {
        uint256 chi = susds.chi();
        assertGe(chi, RAY, "chi should be >= RAY (accumulator starts at 1.0)");
    }

    function test_fork_rhoIsRecentTimestamp() public view {
        uint256 rho = susds.rho();
        assertGt(rho, 1704067200, "rho should be after 2026-02-06");
        assertLe(rho, block.timestamp, "rho should not be in the future");
    }

    function test_fork_payloadMatchesDirectReads() public {
        uint256 expectedSsr = susds.ssr();
        uint256 expectedChi = susds.chi();
        uint256 expectedRho = susds.rho();

        uint256 fee = endpoint.nativeFee();
        vm.deal(operator, fee);

        vm.prank(operator);
        forwarder.forward{value: fee}(DST_EID, "");

        bytes memory payload = endpoint.lastMessage();
        (uint256 ssr, uint256 chi, uint256 rho) = abi.decode(payload, (uint256, uint256, uint256));

        assertEq(ssr, expectedSsr, "payload ssr should match direct read");
        assertEq(chi, expectedChi, "payload chi should match direct read");
        assertEq(rho, expectedRho, "payload rho should match direct read");
    }

    function test_fork_quoteWorksWithRealData() public view {
        MessagingFee memory fee = forwarder.quote(DST_EID, "", false);
        assertGt(fee.nativeFee, 0, "quote should return non-zero fee");
    }
}
