import { XDAOToken } from "src/XDAOToken.sol";
import { BaseLaunchpad } from "src/BaseLaunchpad.sol";
import { Utils } from "src/Utils.sol";
import { BaseLaunchpadTest } from "./Base.t.sol";
import { ILaunchCode } from "src/interfaces/ILaunchCode.sol";

contract BasicLaunchpadTests is BaseLaunchpadTest {

    function setUp() public virtual override(BaseLaunchpadTest) {
        super.setUp();
    }

    /*
        curator actions
    */
    function  test_curate_encodesID() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));

        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);
        assertEq(launchpad._encodeID(0, curator), curationID);

        Utils.AuctionMetadata memory meta = _launchMetadata(address(bioToken));
        emit log_named_uint("TPA contract: startTime --", meta.startTime);
        emit log_named_address("TPA contract: giveToken --", meta.giveToken);
        emit log_named_uint("TPA contract: totalGive --", meta.totalGive);
        emit log_named_address("TPA contract: wantToken --", meta.wantToken);
        emit log_named_address("TPA contract: manager --", meta.manager);
        // TODO assertEq(curationID, uint256(id1 |= encodedValue));
    }

    function  test__encodeID_storesAppIdAndCurator() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));

        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);
        // TODO copy _decodeCode here. dont want to usee contract bc that could theoretically just be looking at storage
        (uint96 appID, address curatorID) = launchpad._decodeID(curationID);
        assertEq(appID, 0);
        assertEq(curatorID, curator);
    }

    // TODO for these _mustBeSTATUS tests. could i just vm. to manually change state values instead of going through the whole process
    function  test_curate_mustBeSUBMITTED() public {
        vbioToken.mint(curator, 100);

        vm.prank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.NULL,
                BaseLaunchpad.AplicationStatus.SUBMITTED
            )
        );
        launchpad.curate(0, 100);
        
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.prank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.ACCEPTED,
                BaseLaunchpad.AplicationStatus.SUBMITTED
            )
        );
        launchpad.curate(0, 100);

        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        launchpad.reject(1);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.REJECTED,
                BaseLaunchpad.AplicationStatus.SUBMITTED
            )
        );
        vm.prank(curator);
        launchpad.curate(1, 100);

        launchpad.submit(operator, bytes32(0));
        vm.prank(curator);
        launchpad.curate(2, 100);
    }

    function  test_curate_mustStakeOver0() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.MustStakeOver0BIO.selector));
        vm.prank(curator);
        launchpad.curate(0, 0);
    }

    function  test_curate_mustHaveAvailableVbioBalance() public {
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.InsufficientVbioBalance.selector));
        vm.prank(curator);
        launchpad.curate(0, 100);

    }

    function  test_curate_increasesTotalStakedByAmount() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        (, , , ,, uint256 totalStaked, ) = launchpad.apps(0);
        assertEq(totalStaked, 0);
        
        vm.prank(curator);
        launchpad.curate(0, 100);
        (, , , ,, uint256 totalStaked_2, ) = launchpad.apps(0);
        assertEq(totalStaked_2, 100);
    }

    function  test_curate_failsOverMaxDeposit(uint96 amount) public {
        if(amount <= type(uint128).max) return;  // not in logic, set in Application.totalStaked uint128
        vbioToken.mint(curator, amount);
        launchpad.submit(operator, bytes32(0));
        uint256 totalStaked = launchpad.vbioLocked(curator);
        assertEq(totalStaked, 0);
        
        vm.expectRevert(); // TODO uint overflow
        vm.prank(curator);
        launchpad.curate(0, amount);

        // vm.expectRevert(); // TODO uint overflow
        // vm.prank(curator);
        // launchpad.curate(0, type(uint128).max);
    }

    function  test_curate_increasesVbioLockedForCurator() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        uint256 totalStaked = launchpad.vbioLocked(curator);
        assertEq(totalStaked, 0);
        
        vm.prank(curator);
        launchpad.curate(0, 100);
        uint256 totalStaked_2 = launchpad.vbioLocked(curator);
        assertEq(totalStaked_2, 100);

    }

    function  test_curate_increasesCurationStakeByAmount(uint96 amount) public {
        vbioToken.mint(curator, amount);
        launchpad.submit(operator, bytes32(0));
        uint256 curationID = launchpad._encodeID(0, curator);
        uint256 amountStaked = launchpad.curations(curationID);
        uint256 totalStaked = launchpad.vbioLocked(curator);
        assertEq(amountStaked, 0);
        assertEq(totalStaked, 0);
        
        vm.prank(curator);
        launchpad.curate(0, amount);
        uint256 amountStaked_2 = launchpad.curations(curationID);
        uint256 totalStaked_2 = launchpad.vbioLocked(curator);
        assertEq(amountStaked_2, amount);
        assertEq(totalStaked_2, amount);
    }

    function  test_claim_mustBeCurator() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);

        vm.prank(operator);
        launchpad.reject(0);
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotCurator.selector));
        launchpad.claim(curationID);
    }

    function _curateAndLaunch(address curator_, uint96 amount_) public returns(address token, address auction) {
        vbioToken.mint(curator_, amount_);
        launchpad.submit(operator, bytes32(0));
        vm.prank(curator_);
        launchpad.curate(0, amount_);
        vm.prank(operator);
        (token, auction) = _accept(0);
        launchpad.graduate(0, xdao);
        auction = launchpad.launch(0, _launchMetadata(token));
    }

    function  test_claim_mustBeLAUNCHED() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);


        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.SUBMITTED,
                BaseLaunchpad.AplicationStatus.LAUNCHED
            )
        );
        vm.prank(curator);
        launchpad.claim(curationID);

        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.ACCEPTED,
                BaseLaunchpad.AplicationStatus.LAUNCHED
            )
        );
        vm.prank(curator);
        launchpad.claim(curationID);

        vm.prank(operator);
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.REMOVED,
                BaseLaunchpad.AplicationStatus.LAUNCHED
            )
        );
        vm.prank(curator);
        launchpad.claim(curationID); // Users have to call uncurate() to unlook vbio when REJECTED


        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        vm.prank(curator);
        uint256 curationID2 = launchpad.curate(1, 100);
        vm.prank(operator);
        (address token_1, address auction_1) = _accept(1);
        vm.prank(operator);
        launchpad.graduate(1, xdao);
        vm.prank(xdao);
        launchpad.launch(1, _launchMetadata(address(token_1)));

        (BaseLaunchpad.AplicationStatus status_2,, uint16 rewardProgramID_2, address program_2, address gov_2, uint256 totalStaked_2, address token_2) = launchpad.apps(0);
        assertEq(uint256(status_2), uint256(BaseLaunchpad.AplicationStatus.LAUNCHED));

        vm.prank(curator);
        launchpad.claim(curationID2); // TODO fix _encode/decodeID functions
    }

    function  test_claim_maintainsTokenBalances() public {
        // invariant. address[] allClaimers for curations[cid] * r.totalCuratorRewards / app.totalStaked <= xdaoToken.balanceOf(launchpad) - r.totalLiquidityReserves

    }

    function  test_claim_mustHaveUnclaimedStake() public {
        launchpad.submit(operator, bytes32(0));
        vbioToken.mint(curator, 100);
        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);
        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.prank(operator);
        launchpad.graduate(0, xdao);
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(token_0)));

        uint256 fakeID = launchpad._encodeID(55, curator);
        vm.prank(curator);
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector, BaseLaunchpad.AplicationStatus.NULL, BaseLaunchpad.AplicationStatus.LAUNCHED));
        launchpad.claim(fakeID);

        vm.prank(curator);
        launchpad.claim(curationID);
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.RewardsAlreadyClaimed.selector));
        vm.prank(curator);
        launchpad.claim(curationID);
    }

    function  test_claim_removesCurationData() public {
        launchpad.submit(operator, bytes32(0));
        vbioToken.mint(curator, 100);

        uint256 curationID = launchpad._encodeID(0, curator);
        uint256 amount0 = launchpad.curations(curationID);
        assertEq(amount0, 0);

        vm.prank(curator);
        launchpad.curate(0, 100);

        uint256 amount1 = launchpad.curations(curationID);
        assertEq(amount1, 100);

        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.prank(operator);
        launchpad.graduate(0, xdao);
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(token_0)));

        vm.prank(curator);
        launchpad.claim(curationID);  // TODO fix _encode/decodeID functions
        uint256 amount2 = launchpad.curations(curationID);

        assertEq(amount2, 0);
    }

    function  test_claim_distributesRewardAmount() public {
        // TODO: Currently no direct token incentives to curators
    }


    function  test_uncurate_reducesVbioLocked() public {
        launchpad.submit(operator, bytes32(0));
        vbioToken.mint(curator, 100);

        uint256 amount0 = launchpad.vbioLocked(curator);
        assertEq(amount0, 0);

        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);

        uint256 amount1 = launchpad.vbioLocked(curator);
        assertEq(amount1, 100);

        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.prank(operator);
        launchpad.graduate(0, xdao);
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(token_0)));

        vm.prank(curator);
        launchpad.claim(curationID);  // TODO fix _encode/decodeID functions
        uint256 amount2 = launchpad.vbioLocked(curator);

        assertEq(amount2, 0);
    }

    

    /*
        bioDAO actions
    */

    function  test_submit_applicantID_increments(uint8 applicants) public {
        for(uint i; i < applicants; i++) {
            assertEq(launchpad.nextApplicantId(), i);
            launchpad.submit(operator, bytes32(0));
        }
    }

    function  test_submit_savesData() public {
        (BaseLaunchpad.AplicationStatus status,, uint16 rewardProgramID, address program, address gov, uint256 totalStaked, address token) = launchpad.apps(0);
        assertEq(uint256(status), uint256(BaseLaunchpad.AplicationStatus.NULL));
        assertEq(rewardProgramID, 0);
        assertEq(program, address(0));
        assertEq(totalStaked, uint128(0));
        assertEq(gov, address(0));
        assertEq(token, address(0));
        
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.AplicationStatus status_2,, uint16 rewardProgramID_2, address program_2, address gov_2, uint256 totalStaked_2, address token_2) = launchpad.apps(0);
        assertEq(uint256(status_2), uint256(BaseLaunchpad.AplicationStatus.SUBMITTED));
        assertEq(rewardProgramID_2, 0);
        assertEq(program_2, operator);
        assertEq(totalStaked_2, uint128(0));
        assertEq(gov_2, address(0));
        assertEq(token_2, address(0));
    }

    function test_launch_mustBeXDAO() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);
        vm.prank(operator);
        launchpad.graduate(0, xdao);

        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotApplicationOwner.selector));
        vm.prank(operator);
        launchpad.launch(0, _launchMetadata(address(token)));
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotApplicationOwner.selector));
        vm.prank(bioNetwork);
        launchpad.launch(0, _launchMetadata(address(token)));

        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(token)));
    } 

    function  test_launch_statusMustBeCOMPLETED() public {
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.SUBMITTED,
                BaseLaunchpad.AplicationStatus.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(bioToken)));

        vm.prank(operator);
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.REJECTED,
                BaseLaunchpad.AplicationStatus.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(bioToken)));
        
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(1);

        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.ACCEPTED,
                BaseLaunchpad.AplicationStatus.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(1, _launchMetadata(address(bioToken)));

        /** Can finally launch() once marked completed on graduate() */
        vm.prank(operator);
        launchpad.graduate(1, xdao);

        vm.prank(xdao);
        launchpad.launch(1, _launchMetadata(address(bioToken)));
    }
    
    function  test_launch_createsAuction() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.prank(operator);
        launchpad.graduate(0, xdao);

        vm.prank(xdao);
        address auction = launchpad.launch(0, _launchMetadata(address(bioToken)));   
        assertNotEq(auction, address(0));

        // TODO how to ensure auction is the launchcode we expdect? Do we have some introspection on auction contracts? how to type/codify/just stirngs?
    }

      
    function  test_launch_mustUseTokensFromCaller() public {
        revert();
        // launchpad.submit(operator, bytes32(0));
        // vm.prank(operator);
        // (address token_0, address auction_0) = _accept(0);
        // vm.prank(operator);
        // launchpad.graduate(0, xdao);

        // vm.prank(xdao);
        // address auction = launchpad.launch(0, _launchMetadata(address(bioToken)));   
        // assertNotEq(auction, address(0));

        // TODO how to ensure auction is the launchcode we expdect? Do we have some introspection on auction contracts? how to type/codify/just stirngs?
    }

    // u would think right? But no! bc of scientist onboarding no address at time of application, proxies submit on their behalf.
    // function  prove_submit_applicant_cant_reapply() public {
    //     vm.prank();
    //     launchpad.submit();

    //     vm.expectRevert(BaseLaunchpad.)

    // }


    /*
        Program Operator Actions
    */

    // TODO check Program rewards heavily
    // function  test_setOperator_setsDefualtRewards (sets to right program + sets right amounts)
    // function  test_setOperator_nextProgramIdIs1
    // function  test_setOperator_capsMaxRewards (checks for reverts)
    // 

    function test_reject_mustBeSUBMITTEDorACCEPTED() public {
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotProgramOperator.selector));
        launchpad.reject(0);

        vm.startPrank(operator);
        // cant reject a LAUNCHED project
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.AplicationStatus status_0,,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_0), uint256(BaseLaunchpad.AplicationStatus.SUBMITTED));
        (address token_0, address auction_0) = _accept(0);
        (BaseLaunchpad.AplicationStatus status_1,,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_1), uint256(BaseLaunchpad.AplicationStatus.ACCEPTED));
        launchpad.graduate(0, xdao);
        (BaseLaunchpad.AplicationStatus status_2,,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_2), uint256(BaseLaunchpad.AplicationStatus.COMPLETED));
        vm.stopPrank();
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(bioToken)));
        (BaseLaunchpad.AplicationStatus status_3,,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_3), uint256(BaseLaunchpad.AplicationStatus.LAUNCHED));
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.MustClaimOnceLaunched.selector));
        launchpad.reject(0);

        //  reject a SUBMITTED project
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.AplicationStatus status_4,,,,,,) = launchpad.apps(1);
        assertEq(uint256(status_4), uint256(BaseLaunchpad.AplicationStatus.SUBMITTED));
        launchpad.reject(1);
        (BaseLaunchpad.AplicationStatus status_5,,,,,,) = launchpad.apps(1);
        assertEq(uint256(status_5), uint256(BaseLaunchpad.AplicationStatus.REJECTED));
        
        //  reject a ACCEPTED project
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.AplicationStatus status_6,,,,,,) = launchpad.apps(2);
        assertEq(uint256(status_6), uint256(BaseLaunchpad.AplicationStatus.SUBMITTED));
        _accept(2);
        (BaseLaunchpad.AplicationStatus status_7,,,,,,) = launchpad.apps(2);
        assertEq(uint256(status_7), uint256(BaseLaunchpad.AplicationStatus.ACCEPTED));
        launchpad.reject(2);
        (BaseLaunchpad.AplicationStatus status_8,,,,,,) = launchpad.apps(2);
        assertEq(uint256(status_8), uint256(BaseLaunchpad.AplicationStatus.REMOVED));

        //  reject a COMPLETED project
        launchpad.submit(operator, bytes32(0));
        _accept(3);
        launchpad.graduate(3, xdao);
        (BaseLaunchpad.AplicationStatus status_9,,,,,,) = launchpad.apps(3);
        assertEq(uint256(status_9), uint256(BaseLaunchpad.AplicationStatus.COMPLETED));
        launchpad.reject(3);
        (BaseLaunchpad.AplicationStatus status_10,,,,,,) = launchpad.apps(3);
        assertEq(uint256(status_10), uint256(BaseLaunchpad.AplicationStatus.REMOVED));

        // rejecting a REJECTED/REMOVED project does nothing
        launchpad.submit(operator, bytes32(0));
        launchpad.reject(4);
        (BaseLaunchpad.AplicationStatus status_11,,,,,,) = launchpad.apps(4);
        assertEq(uint256(status_11), uint256(BaseLaunchpad.AplicationStatus.REJECTED));
        launchpad.reject(4);
        launchpad.reject(4);
        (BaseLaunchpad.AplicationStatus status_12,,,,,,) = launchpad.apps(4);
        assertEq(uint256(status_12), uint256(BaseLaunchpad.AplicationStatus.REJECTED));

        launchpad.submit(operator, bytes32(0));
        _accept(5);
        launchpad.reject(5);
        (BaseLaunchpad.AplicationStatus status_13,,,,,,) = launchpad.apps(5);
        assertEq(uint256(status_13), uint256(BaseLaunchpad.AplicationStatus.REMOVED));
        launchpad.reject(5);
        (BaseLaunchpad.AplicationStatus status_14,,,,,,) = launchpad.apps(5);
        assertEq(uint256(status_14), uint256(BaseLaunchpad.AplicationStatus.REMOVED));

        vm.stopPrank();
    }


    function test_reject_mustBeOperator() public {
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotProgramOperator.selector));
        launchpad.reject(0);

        vm.prank(operator);
        launchpad.reject(0);
    } 

    function test_accept_mustBeOperator() public {
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotProgramOperator.selector));
        (address token_0, address auction_0) = _accept(0);

        vm.prank(operator);
        (address token, address auction) = _accept(0);
    } 

    function test_accept_reservesXdaoTokenBasedOnProgramRates() public {
        launchpad.submit(operator, bytes32(0));

        vm.prank(operator);
        (address token, address auction) = _accept(0);

        (BaseLaunchpad.AplicationStatus status_2,, uint16 rewardProgramID_2, address program_2, address gov_2, uint256 totalStaked_2, address token_2) = launchpad.apps(0);
        assertEq(token, token_2);

        (uint128 liqReserves, uint128 curatorReserves) = launchpad.rewards(0);

        (uint16 liqReserveRate, uint16 curatorReserveRate) = launchpad.pRewards(operator, 0);

        assertEq(liqReserves, (uint256(liqReserveRate) * 1_000_000 * 1e18) / 10_000); // 10_000 = BPS_COEFFICIENT
        assertEq(curatorReserves, (uint256(curatorReserveRate) * 1_000_000 * 1e18) / 10_000); // 10_000 = BPS_COEFFICIENT
    } 

    function test_accept_mustBeSUBMITTEDApp() public {
        // no app in storage so operator is null
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotProgramOperator.selector));
        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);

        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);
    }

    function test_accept_mustDeployNewToken() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);

        assertNotEq(token, address(0));
    }


    function test_accept_mustMintReservesToAuction() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);

        (uint128 liqReserves, uint128 curatorReserves) = launchpad.rewards(0);
        assertGt(XDAOToken(token).balanceOf(address(launchpad)), uint256(liqReserves));
        assertGt(XDAOToken(token).balanceOf(auction), uint256(curatorReserves));
    }

    function test_accept_mustDeployCuratorAuction() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);


        (uint32 startTime, uint32 endTime,  address wantToken, uint256 wantAmount, address giveToken, uint256 giveAmount) = ILaunchCode(auction).getAuctionData();
        // TODO these hardcoded curator auction params arent consts in the contract yet, dont think they need to be
        assertEq(startTime, block.timestamp + 1 days);
        assertEq(endTime, block.timestamp + 8 days);

        assertEq(wantToken, address(usdc));
        assertEq(wantAmount, block.timestamp + 8 days);
        assertEq(giveToken, token);
        (, uint256 totalCuratorReserves) = launchpad.rewards(0);
        assertEq(giveAmount, totalCuratorReserves);
    }

    function test_accept_launchCodeTPAAuction() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        vm.prank(curator);
        uint256 curationID = launchpad.curate(0, 100);
        vm.prank(operator);
        (address token, address auction) = _accept(0);
        uint256 amount = 500_000 * 1e18;
        usdc.mint(curator, amount);
        vm.prank(curator);
        usdc.approve(auction, amount);
        vm.prank(curator);
        launchpad.claim(curationID);

        
        // TODO these hardcoded curator auction params arent consts in the contract yet, dont think they need to be

    }

    function test_graduate_mustBeOperator() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);

        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.NotProgramOperator.selector));
        launchpad.graduate(0, xdao);

        vm.prank(operator);
        launchpad.graduate(0, xdao);
    } 

    function test_graduate_mustBeACCEPTEDApp() public {
        vm.startPrank(operator);
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.SUBMITTED,
                BaseLaunchpad.AplicationStatus.ACCEPTED
            )
        );
        launchpad.graduate(0, xdao);
        
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.REJECTED,
                BaseLaunchpad.AplicationStatus.ACCEPTED
            )
        );
        launchpad.graduate(0, xdao);


        launchpad.submit(operator, bytes32(0));
        _accept(1);
        launchpad.graduate(1, xdao);

        // cant graduate once graudated already
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.AplicationStatus.COMPLETED,
                BaseLaunchpad.AplicationStatus.ACCEPTED
            )
        );
        launchpad.graduate(1, xdao);
        vm.stopPrank();
    }

    function _launchMetadata(address token) internal returns (Utils.AuctionMetadata memory) {
        bytes memory customLaunchData;
        return Utils.AuctionMetadata({
            launchCode: curatorAuction,
            manager: bioNetwork,
            totalGive: 0,
            giveToken: token,
            wantToken: address(0), // TODO hardcode? should be added by LaunchCode
            totalWant: 0,
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        });
    }

    function _launchMetadata(address token, address launchCode, bytes memory customLaunchData) internal returns (Utils.AuctionMetadata memory) {
        return Utils.AuctionMetadata({
            launchCode: launchCode,
            manager: bioNetwork,
            totalGive: 0,
            totalWant: 0,
            giveToken: token,
            wantToken: address(usdc),
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        });
    }

    function _accept(uint96 id) internal returns(address token, address auction) {
        return launchpad.accept(id, BaseLaunchpad.OrgMetadata({
            name: "test",
            symbol: "tester",
            maxSupply: 1_000_000 ether,
            valuation: 5e15 // $5M USDC
        }));
    }

}