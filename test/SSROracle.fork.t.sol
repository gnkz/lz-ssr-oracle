// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {SSROracle} from "../contracts/SSROracle.sol";
import {SSRForwarder} from "../contracts/SSRForwarder.sol";
import {ISUSDS} from "../contracts/interfaces/ISUSDS.sol";
import {MockLZEndpoint} from "../contracts/mocks/MockLZEndpoint.sol";
import {Origin} from "lz-protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @notice Fork-based integration tests for SSROracle against real sUSDS data from mainnet
contract SSROracleForkTest is Test {
    SSROracle public oracle;
    MockLZEndpoint public endpoint;
    ISUSDS public susds;

    address public owner = makeAddr("owner");

    uint32 public constant LOCAL_EID = 30383; // Plasma
    uint32 public constant SRC_EID = 30101; // Mainnet

    address public constant SUSDS_MAINNET = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    uint256 public constant RAY = 1e27;

    bytes32 public peerAddress;

    function setUp() public {
        vm.createSelectFork("mainnet", 24_397_070);

        susds = ISUSDS(SUSDS_MAINNET);
        endpoint = new MockLZEndpoint(LOCAL_EID);

        vm.prank(owner);
        oracle = new SSROracle(address(endpoint), owner);

        peerAddress = bytes32(uint256(uint160(makeAddr("forwarder"))));
        vm.prank(owner);
        oracle.setPeer(SRC_EID, peerAddress);
    }

    // ── Helpers ──────────────────────────────────────────────

    function _deliver(uint256 ssr_, uint256 chi_, uint256 rho_) internal {
        Origin memory origin = Origin({srcEid: SRC_EID, sender: peerAddress, nonce: 1});
        vm.prank(address(endpoint));
        oracle.lzReceive(origin, bytes32(0), abi.encode(ssr_, chi_, rho_), address(0), "");
    }

    // ═══════════════════════════════════════════════════════
    //  Receive and store real sUSDS data
    // ═══════════════════════════════════════════════════════

    function test_fork_receivesRealSSRData() public {
        uint256 ssr = susds.ssr();
        uint256 chi = susds.chi();
        uint256 rho = susds.rho();

        _deliver(ssr, chi, rho);

        (uint96 storedSsr, uint120 storedChi, uint40 storedRho) = oracle.ssrData();
        assertEq(uint256(storedSsr), ssr, "stored ssr should match real value");
        assertEq(uint256(storedChi), chi, "stored chi should match real value");
        assertEq(uint256(storedRho), rho, "stored rho should match real value");
    }

    function test_fork_realValuesMatchExpectedAtBlock() public {
        uint256 ssr = susds.ssr();
        uint256 chi = susds.chi();
        uint256 rho = susds.rho();

        assertEq(ssr, 1000000001243680656318820312, "ssr should equal value at block");
        assertEq(chi, 1085599589085496159450618781, "chi should equal value at block");
        assertEq(rho, 1770372311, "rho should equal value at block");
    }

    // ═══════════════════════════════════════════════════════
    //  Packing preserves real values
    // ═══════════════════════════════════════════════════════

    function test_fork_dataPackingPreservesRealValues() public {
        uint256 ssr = susds.ssr();
        uint256 chi = susds.chi();
        uint256 rho = susds.rho();

        _deliver(ssr, chi, rho);

        (uint96 storedSsr, uint120 storedChi, uint40 storedRho) = oracle.ssrData();

        // Verify no truncation from packing into smaller types
        assertEq(uint256(storedSsr), ssr, "ssr should survive uint96 packing");
        assertEq(uint256(storedChi), chi, "chi should survive uint120 packing");
        assertEq(uint256(storedRho), rho, "rho should survive uint40 packing");
    }

    // ═══════════════════════════════════════════════════════
    //  getConversionRate with real data
    // ═══════════════════════════════════════════════════════

    function test_fork_conversionRateWithRealData() public {
        uint256 ssr = susds.ssr();
        uint256 chi = susds.chi();
        uint256 rho = susds.rho();

        _deliver(ssr, chi, rho);

        // Warp to rho so timeDelta=0, rate should equal chi
        vm.warp(rho);
        uint256 rate = oracle.getConversionRate();
        assertEq(rate, chi, "rate at rho should equal chi");
    }

    function test_fork_conversionRateGrowsOverTime() public {
        uint256 ssr = susds.ssr();
        uint256 chi = susds.chi();
        uint256 rho = susds.rho();

        _deliver(ssr, chi, rho);

        vm.warp(rho);
        uint256 rateAtRho = oracle.getConversionRate();

        vm.warp(rho + 3600);
        uint256 rateAfter1h = oracle.getConversionRate();

        vm.warp(rho + 86400);
        uint256 rateAfter1d = oracle.getConversionRate();

        assertGt(rateAfter1h, rateAtRho, "rate should grow after 1 hour");
        assertGt(rateAfter1d, rateAfter1h, "rate should grow after 1 day");
    }

    function test_fork_conversionRateAboveRAY() public {
        uint256 ssr = susds.ssr();
        uint256 chi = susds.chi();
        uint256 rho = susds.rho();

        _deliver(ssr, chi, rho);

        vm.warp(rho);
        uint256 rate = oracle.getConversionRate();
        assertGt(rate, RAY, "rate should be > RAY (chi has accrued interest)");
    }

    // ═══════════════════════════════════════════════════════
    //  End-to-end: forwarder → oracle with real sUSDS
    // ═══════════════════════════════════════════════════════

    function test_fork_endToEndForwarderToOracle() public {
        // Deploy forwarder pointing at real sUSDS
        MockLZEndpoint fwdEndpoint = new MockLZEndpoint(SRC_EID);
        address operator = makeAddr("operator");

        vm.startPrank(owner);
        SSRForwarder forwarder = new SSRForwarder(address(fwdEndpoint), owner, SUSDS_MAINNET);
        forwarder.setPeer(LOCAL_EID, bytes32(uint256(uint160(address(oracle)))));
        forwarder.setOperator(operator, true);
        vm.stopPrank();

        // Forward real data
        uint256 fee = fwdEndpoint.nativeFee();
        vm.deal(operator, fee);
        vm.prank(operator);
        forwarder.forward{value: fee}(LOCAL_EID, "");

        // Extract the payload the forwarder sent
        bytes memory payload = fwdEndpoint.lastMessage();

        // Deliver payload to oracle as if it arrived via LayerZero
        Origin memory origin = Origin({srcEid: SRC_EID, sender: peerAddress, nonce: 1});
        vm.prank(address(endpoint));
        oracle.lzReceive(origin, bytes32(0), payload, address(0), "");

        // Verify oracle stored data matches direct sUSDS reads
        (uint96 storedSsr, uint120 storedChi, uint40 storedRho) = oracle.ssrData();
        assertEq(uint256(storedSsr), susds.ssr(), "oracle ssr should match sUSDS");
        assertEq(uint256(storedChi), susds.chi(), "oracle chi should match sUSDS");
        assertEq(uint256(storedRho), susds.rho(), "oracle rho should match sUSDS");

        // Verify getConversionRate returns a sensible value
        vm.warp(susds.rho());
        uint256 rate = oracle.getConversionRate();
        assertEq(rate, susds.chi(), "conversion rate at rho should equal chi");
    }
}
