// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {SSROracle} from "../contracts/SSROracle.sol";
import {MockLZEndpoint} from "../contracts/mocks/MockLZEndpoint.sol";
import {Origin} from "lz-protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SSROracleTest is Test {
    SSROracle public oracle;
    MockLZEndpoint public endpoint;

    address public owner = makeAddr("owner");
    address public stranger = makeAddr("stranger");

    uint32 public constant LOCAL_EID = 30383; // Plasma
    uint32 public constant SRC_EID = 30101; // Mainnet

    uint256 public constant RAY = 1e27;

    // ~5% APY per-second rate in RAY
    uint256 public constant SSR = 1000000001547125957863212448;
    uint256 public constant CHI = 1050000000000000000000000000; // 1.05 RAY
    uint256 public constant RHO = 1700000000;

    bytes32 public peerAddress;

    function setUp() public {
        endpoint = new MockLZEndpoint(LOCAL_EID);

        vm.prank(owner);
        oracle = new SSROracle(address(endpoint), owner);

        // Set peer (the SSRForwarder on mainnet)
        peerAddress = bytes32(uint256(uint160(makeAddr("forwarder"))));
        vm.prank(owner);
        oracle.setPeer(SRC_EID, peerAddress);

        // Set block.timestamp to a known value above RHO
        vm.warp(RHO);
    }

    // ── Helpers ──────────────────────────────────────────────

    function _buildPayload(uint256 ssr_, uint256 chi_, uint256 rho_) internal pure returns (bytes memory) {
        return abi.encode(ssr_, chi_, rho_);
    }

    function _buildOrigin(uint64 nonce_) internal view returns (Origin memory) {
        return Origin({srcEid: SRC_EID, sender: peerAddress, nonce: nonce_});
    }

    function _deliver(uint256 ssr_, uint256 chi_, uint256 rho_) internal {
        vm.prank(address(endpoint));
        oracle.lzReceive(_buildOrigin(1), bytes32(0), _buildPayload(ssr_, chi_, rho_), address(0), "");
    }

    // ═══════════════════════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════════════════════

    function test_constructor_setsEndpoint() public view {
        assertEq(address(oracle.endpoint()), address(endpoint));
    }

    function test_constructor_setsOwner() public view {
        assertEq(oracle.owner(), owner);
    }

    function test_constructor_ssrDataIsZero() public view {
        (uint96 ssr, uint120 chi, uint40 rho) = oracle.ssrData();
        assertEq(ssr, 0);
        assertEq(chi, 0);
        assertEq(rho, 0);
    }

    // ═══════════════════════════════════════════════════════
    //  Constants
    // ═══════════════════════════════════════════════════════

    function test_RAY_constant() public view {
        assertEq(oracle.RAY(), 1e27);
    }

    // ═══════════════════════════════════════════════════════
    //  _lzReceive — successful updates
    // ═══════════════════════════════════════════════════════

    function test_lzReceive_updatesSSRData() public {
        _deliver(SSR, CHI, RHO);

        (uint96 ssr, uint120 chi, uint40 rho) = oracle.ssrData();
        assertEq(ssr, uint96(SSR));
        assertEq(chi, uint120(CHI));
        assertEq(rho, uint40(RHO));
    }

    function test_lzReceive_emitsSSRDataUpdated() public {
        vm.expectEmit(false, false, false, true);
        emit SSROracle.SSRDataUpdated(0, SSR, 0, CHI, 0, RHO);

        _deliver(SSR, CHI, RHO);
    }

    function test_lzReceive_emitsSSRDataUpdated_withPreviousValues() public {
        _deliver(SSR, CHI, RHO);

        uint256 newSsr = 1000000002000000000000000000;
        uint256 newChi = 1100000000000000000000000000;
        uint256 newRho = RHO + 100;

        vm.expectEmit(false, false, false, true);
        emit SSROracle.SSRDataUpdated(uint96(SSR), newSsr, uint120(CHI), newChi, uint40(RHO), newRho);

        _deliver(newSsr, newChi, newRho);
    }

    function test_lzReceive_acceptsEqualRho() public {
        _deliver(SSR, CHI, RHO);

        // Same rho should succeed (not stale, only older rho is rejected)
        uint256 newChi = CHI + 1;
        _deliver(SSR, newChi, RHO);

        (, uint120 chi,) = oracle.ssrData();
        assertEq(chi, uint120(newChi));
    }

    function test_lzReceive_acceptsNewerRho() public {
        _deliver(SSR, CHI, RHO);

        uint256 newerRho = RHO + 3600;
        uint256 newChi = 1060000000000000000000000000;
        _deliver(SSR, newChi, newerRho);

        (uint96 ssr, uint120 chi, uint40 rho) = oracle.ssrData();
        assertEq(ssr, uint96(SSR));
        assertEq(chi, uint120(newChi));
        assertEq(rho, uint40(newerRho));
    }

    function test_lzReceive_multipleUpdates() public {
        _deliver(SSR, CHI, RHO);

        uint256 rho2 = RHO + 100;
        uint256 chi2 = CHI + 100;
        _deliver(SSR, chi2, rho2);

        uint256 rho3 = rho2 + 100;
        uint256 chi3 = chi2 + 100;
        _deliver(SSR, chi3, rho3);

        (, uint120 chi, uint40 rho) = oracle.ssrData();
        assertEq(chi, uint120(chi3));
        assertEq(rho, uint40(rho3));
    }

    // ═══════════════════════════════════════════════════════
    //  _lzReceive — stale data rejection
    // ═══════════════════════════════════════════════════════

    function test_lzReceive_revertsOnStaleData() public {
        _deliver(SSR, CHI, RHO);

        vm.expectRevert(SSROracle.StaleData.selector);
        _deliver(SSR, CHI, RHO - 1);
    }

    function test_lzReceive_revertsOnMuchOlderRho() public {
        _deliver(SSR, CHI, RHO);

        vm.expectRevert(SSROracle.StaleData.selector);
        _deliver(SSR, CHI, RHO - 3600);
    }

    // ═══════════════════════════════════════════════════════
    //  _lzReceive — access control
    // ═══════════════════════════════════════════════════════

    function test_lzReceive_revertsIfNotEndpoint() public {
        vm.expectRevert();
        vm.prank(stranger);
        oracle.lzReceive(_buildOrigin(1), bytes32(0), _buildPayload(SSR, CHI, RHO), address(0), "");
    }

    function test_lzReceive_revertsIfWrongPeer() public {
        Origin memory badOrigin = Origin({srcEid: SRC_EID, sender: bytes32(uint256(0xdead)), nonce: 1});

        vm.expectRevert();
        vm.prank(address(endpoint));
        oracle.lzReceive(badOrigin, bytes32(0), _buildPayload(SSR, CHI, RHO), address(0), "");
    }

    function test_lzReceive_revertsIfUnknownSrcEid() public {
        Origin memory badOrigin = Origin({srcEid: 99999, sender: peerAddress, nonce: 1});

        vm.expectRevert();
        vm.prank(address(endpoint));
        oracle.lzReceive(badOrigin, bytes32(0), _buildPayload(SSR, CHI, RHO), address(0), "");
    }

    // ═══════════════════════════════════════════════════════
    //  getConversionRate — zero/initial state
    // ═══════════════════════════════════════════════════════

    function test_getConversionRate_returnsZeroBeforeAnyUpdate() public view {
        // ssrData is all zeros, so chi=0 → rate = 0 * anything / RAY = 0
        assertEq(oracle.getConversionRate(), 0);
    }

    // ═══════════════════════════════════════════════════════
    //  getConversionRate — no time elapsed (timeDelta = 0)
    // ═══════════════════════════════════════════════════════

    function test_getConversionRate_returnsChi_whenNoTimeElapsed() public {
        // Set rho = block.timestamp so timeDelta = 0
        // _rpow(ssr, 0) = RAY, so rate = chi * RAY / RAY = chi
        _deliver(SSR, CHI, block.timestamp);

        assertEq(oracle.getConversionRate(), CHI);
    }

    function test_getConversionRate_returnsRAY_whenChiIsRAY_andNoTimeElapsed() public {
        _deliver(SSR, RAY, block.timestamp);

        assertEq(oracle.getConversionRate(), RAY);
    }

    // ═══════════════════════════════════════════════════════
    //  getConversionRate — with time elapsed
    // ═══════════════════════════════════════════════════════

    function test_getConversionRate_compoundsOneSecond() public {
        _deliver(SSR, RAY, block.timestamp);

        // Advance 1 second
        vm.warp(block.timestamp + 1);

        // _rpow(SSR, 1) = SSR, so rate = RAY * SSR / RAY = SSR
        assertEq(oracle.getConversionRate(), SSR);
    }

    function test_getConversionRate_compoundsTwoSeconds() public {
        _deliver(SSR, RAY, block.timestamp);

        vm.warp(block.timestamp + 2);

        // _rpow(SSR, 2) = SSR * SSR / RAY
        uint256 expected = SSR * SSR / RAY;
        assertEq(oracle.getConversionRate(), expected);
    }

    function test_getConversionRate_compoundsWithNonUnitChi() public {
        // chi = 1.05 RAY, advance 1 second
        _deliver(SSR, CHI, block.timestamp);

        vm.warp(block.timestamp + 1);

        // rate = CHI * SSR / RAY
        uint256 expected = CHI * SSR / RAY;
        assertEq(oracle.getConversionRate(), expected);
    }

    function test_getConversionRate_compoundsOneHour() public {
        _deliver(SSR, RAY, block.timestamp);

        vm.warp(block.timestamp + 3600);

        // Rate should be slightly above RAY after 1 hour at ~5% APY
        uint256 rate = oracle.getConversionRate();
        assertTrue(rate > RAY, "rate should be > RAY after 1 hour");
        // 5% APY over 1 hour: ~0.00057% increase
        // rate should be < 1.0001 * RAY
        assertTrue(rate < RAY + RAY / 10000, "rate increase should be small for 1 hour");
    }

    function test_getConversionRate_compoundsOneDay() public {
        _deliver(SSR, RAY, block.timestamp);

        vm.warp(block.timestamp + 86400);

        uint256 rate = oracle.getConversionRate();
        assertTrue(rate > RAY, "rate should be > RAY after 1 day");
        // ~0.0137% daily increase at 5% APY
        assertTrue(rate < RAY + RAY / 7000, "rate should be < ~0.014% increase for 1 day");
    }

    function test_getConversionRate_unitRate_noCompounding() public {
        // ssr = RAY (exactly 1.0, 0% interest) → no compounding regardless of time
        _deliver(RAY, CHI, block.timestamp);

        vm.warp(block.timestamp + 365 days);

        // _rpow(RAY, n) = RAY for any n, so rate = CHI * RAY / RAY = CHI
        assertEq(oracle.getConversionRate(), CHI);
    }

    // ═══════════════════════════════════════════════════════
    //  _rpow — tested indirectly through getConversionRate
    // ═══════════════════════════════════════════════════════

    function test_rpow_exponentZero() public {
        // n=0: _rpow(x, 0) = RAY
        _deliver(SSR, RAY, block.timestamp);

        // timeDelta = 0 → rate = RAY * RAY / RAY = RAY
        assertEq(oracle.getConversionRate(), RAY);
    }

    function test_rpow_exponentOne() public {
        _deliver(SSR, RAY, block.timestamp);
        vm.warp(block.timestamp + 1);

        // _rpow(SSR, 1) = SSR
        assertEq(oracle.getConversionRate(), SSR);
    }

    function test_rpow_exponentThree() public {
        // n=3 (odd): tests both odd-initial and loop paths
        _deliver(SSR, RAY, block.timestamp);
        vm.warp(block.timestamp + 3);

        // Manual: _rpow(SSR, 3)
        // z = SSR (3%2!=0)
        // n_=1: x_ = SSR*SSR/RAY; 1%2!=0 → z = SSR * (SSR*SSR/RAY) / RAY = SSR^3/RAY^2
        uint256 ssrSq = SSR * SSR / RAY;
        uint256 expected = SSR * ssrSq / RAY;
        assertEq(oracle.getConversionRate(), expected);
    }

    function test_rpow_exponentFour() public {
        // n=4 (even, power of 2): tests loop-only squaring
        _deliver(SSR, RAY, block.timestamp);
        vm.warp(block.timestamp + 4);

        // _rpow(SSR, 4):
        // z = RAY (4%2==0)
        // n_=2: x_ = SSR*SSR/RAY; 2%2==0 → no multiply
        // n_=1: x_ = (SSR*SSR/RAY)^2/RAY; 1%2!=0 → z = RAY * x_ / RAY = x_
        uint256 ssrSq = SSR * SSR / RAY;
        uint256 expected = ssrSq * ssrSq / RAY;
        assertEq(oracle.getConversionRate(), expected);
    }

    function test_rpow_exponentSeven() public {
        // n=7 (0b111): exercises multiple odd iterations
        _deliver(SSR, RAY, block.timestamp);
        vm.warp(block.timestamp + 7);

        // Compute step by step:
        // z = SSR (7%2!=0), n_=3
        // iter1: x_ = SSR*SSR/RAY = ssrSq; n_=3, 3%2!=0 → z = SSR * ssrSq / RAY; n_=1
        // iter2: x_ = ssrSq*ssrSq/RAY = ssr4; 1%2!=0 → z = z * ssr4 / RAY; n_=0
        uint256 ssrSq = SSR * SSR / RAY;
        uint256 ssr4 = ssrSq * ssrSq / RAY;
        uint256 expected = SSR * ssrSq / RAY;
        expected = expected * ssr4 / RAY;
        assertEq(oracle.getConversionRate(), expected);
    }

    function test_rpow_baseIsRAY_alwaysReturnsRAY() public {
        // _rpow(RAY, n) should always return RAY for any n
        _deliver(RAY, RAY, block.timestamp);

        vm.warp(block.timestamp + 1000);
        assertEq(oracle.getConversionRate(), RAY);

        vm.warp(block.timestamp + 100000);
        assertEq(oracle.getConversionRate(), RAY);
    }

    function test_rpow_largeExponent() public {
        // ~1 year in seconds, should not overflow for reasonable rates
        _deliver(SSR, RAY, block.timestamp);

        vm.warp(block.timestamp + 365 days);

        uint256 rate = oracle.getConversionRate();
        // ~5% APY: rate should be approximately 1.05 RAY
        // Allow some tolerance for discrete compounding vs continuous
        assertTrue(rate > RAY * 104 / 100, "rate should be > 1.04 RAY after 1 year at ~5% APY");
        assertTrue(rate < RAY * 106 / 100, "rate should be < 1.06 RAY after 1 year at ~5% APY");
    }

    // ═══════════════════════════════════════════════════════
    //  SSRData packing
    // ═══════════════════════════════════════════════════════

    function test_packing_preservesValues() public {
        _deliver(SSR, CHI, RHO);

        (uint96 ssr, uint120 chi, uint40 rho) = oracle.ssrData();

        // Verify no truncation occurred
        assertEq(uint256(ssr), SSR);
        assertEq(uint256(chi), CHI);
        assertEq(uint256(rho), RHO);
    }

    function test_packing_maxUint96_ssr() public {
        uint256 maxSsr = type(uint96).max;

        _deliver(maxSsr, CHI, RHO);

        (uint96 ssr,,) = oracle.ssrData();
        assertEq(uint256(ssr), maxSsr);
    }

    function test_packing_maxUint120_chi() public {
        uint256 maxChi = type(uint120).max;

        _deliver(SSR, maxChi, RHO);

        (, uint120 chi,) = oracle.ssrData();
        assertEq(uint256(chi), maxChi);
    }

    function test_packing_maxUint40_rho() public {
        uint256 maxRho = type(uint40).max;
        vm.warp(maxRho);

        _deliver(SSR, CHI, maxRho);

        (,, uint40 rho) = oracle.ssrData();
        assertEq(uint256(rho), maxRho);
    }

    // ═══════════════════════════════════════════════════════
    //  Ownership (inherited from OAppCore)
    // ═══════════════════════════════════════════════════════

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        oracle.transferOwnership(newOwner);

        assertEq(oracle.owner(), newOwner);
    }

    function test_transferOwnership_revertsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        oracle.transferOwnership(stranger);
    }

    // ═══════════════════════════════════════════════════════
    //  Peer management (inherited from OAppCore)
    // ═══════════════════════════════════════════════════════

    function test_setPeer_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        oracle.setPeer(SRC_EID, bytes32(uint256(1)));
    }

    function test_setPeer_updatesPeer() public {
        bytes32 newPeer = bytes32(uint256(0xbeef));

        vm.prank(owner);
        oracle.setPeer(SRC_EID, newPeer);

        assertEq(oracle.peers(SRC_EID), newPeer);
    }

    function test_setPeer_canRemovePeer() public {
        vm.prank(owner);
        oracle.setPeer(SRC_EID, bytes32(0));

        assertEq(oracle.peers(SRC_EID), bytes32(0));
    }

    function test_setPeer_removedPeerBlocksReceive() public {
        vm.prank(owner);
        oracle.setPeer(SRC_EID, bytes32(0));

        vm.expectRevert();
        vm.prank(address(endpoint));
        oracle.lzReceive(_buildOrigin(1), bytes32(0), _buildPayload(SSR, CHI, RHO), address(0), "");
    }

    // ═══════════════════════════════════════════════════════
    //  getConversionRate — after multiple updates
    // ═══════════════════════════════════════════════════════

    function test_getConversionRate_afterUpdate_resetsCompounding() public {
        // First update at t=RHO
        _deliver(SSR, RAY, block.timestamp);

        // Advance 100 seconds
        vm.warp(block.timestamp + 100);
        uint256 rateAfter100s = oracle.getConversionRate();
        assertTrue(rateAfter100s > RAY);

        // New update arrives at current timestamp — resets compounding base
        uint256 newChi = rateAfter100s; // chi updated to reflect accrued interest
        _deliver(SSR, newChi, block.timestamp);

        // No additional time: rate should equal new chi exactly
        assertEq(oracle.getConversionRate(), newChi);

        // Advance 100 seconds again — compounding starts from new chi
        vm.warp(block.timestamp + 100);
        uint256 rateAfterSecond100s = oracle.getConversionRate();
        assertTrue(rateAfterSecond100s > newChi);
    }

    // ═══════════════════════════════════════════════════════
    //  Edge cases
    // ═══════════════════════════════════════════════════════

    function test_lzReceive_fromInitialZeroRho_acceptsAnyRho() public {
        // Initial rho is 0 (default), so any incoming rho >= 0 should succeed
        _deliver(SSR, CHI, 1);

        (, , uint40 rho) = oracle.ssrData();
        assertEq(rho, 1);
    }

    function test_lzReceive_rhoZero_accepted() public {
        // Even rho=0 should be accepted when stored rho is 0
        _deliver(SSR, CHI, 0);

        (uint96 ssr, uint120 chi, uint40 rho) = oracle.ssrData();
        assertEq(uint256(ssr), SSR);
        assertEq(uint256(chi), CHI);
        assertEq(rho, 0);
    }

    function test_getConversionRate_symmetricWithForwarderPayload() public {
        // Verify the oracle correctly decodes the exact payload format the forwarder sends
        bytes memory payload = abi.encode(SSR, CHI, RHO);
        (uint256 decodedSsr, uint256 decodedChi, uint256 decodedRho) =
            abi.decode(payload, (uint256, uint256, uint256));

        assertEq(decodedSsr, SSR);
        assertEq(decodedChi, CHI);
        assertEq(decodedRho, RHO);

        // Deliver via lzReceive and check stored values match
        vm.prank(address(endpoint));
        oracle.lzReceive(_buildOrigin(1), bytes32(0), payload, address(0), "");

        (uint96 storedSsr, uint120 storedChi, uint40 storedRho) = oracle.ssrData();
        assertEq(uint256(storedSsr), SSR);
        assertEq(uint256(storedChi), CHI);
        assertEq(uint256(storedRho), RHO);
    }
}
