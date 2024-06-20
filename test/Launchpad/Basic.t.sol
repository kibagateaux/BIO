import { XDAOToken } from "src/XDAOToken.sol";
import { BaseLaunchpad } from "src/BaseLaunchpad.sol";
import { BaseLaunchpadTest } from "./Base.t.sol";


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
        // TODO assertEq(curationID, uint256(id1 |= encodedValue));
    }

    function  test_curate_mustBeSUBMITTED() public {
        vbioToken.mint(curator, 100);

        vm.prank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.NULL,
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED
            )
        );
        launchpad.curate(0, 100);
        
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.prank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED,
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED
            )
        );
        launchpad.curate(0, 100);

        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        launchpad.reject(1);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.REJECTED,
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED
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
        (, , , , uint128 totalStaked, ) = launchpad.apps(0);
        assertEq(totalStaked, 0);
        
        vm.prank(curator);
        launchpad.curate(0, 100);
        (, , , , uint128 totalStaked_2, ) = launchpad.apps(0);
        assertEq(totalStaked_2, 100);
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

    function  test_curate_increasesCurationStakeByAmount() public {
        vbioToken.mint(curator, 100);
        launchpad.submit(operator, bytes32(0));
        uint256 curationID = launchpad._encodeID(0, curator);
        uint256 totalStaked = launchpad.curations(curationID);
        assertEq(totalStaked, 0);
        
        vm.prank(curator);
        launchpad.curate(0, 100);
        uint256 totalStaked_2 = launchpad.curations(curationID);
        assertEq(totalStaked_2, 100);
    }

    function  test_claim_mustBeCurator() public {


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
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED,
                BaseLaunchpad.APPLICATION_STATUS.LAUNCHED
            )
        );
        vm.prank(curator);
        launchpad.claim(curationID);

        vm.prank(operator);
        (address token_0, address auction_0) = _accept(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED,
                BaseLaunchpad.APPLICATION_STATUS.LAUNCHED
            )
        );
        vm.prank(curator);
        launchpad.claim(curationID);

        vm.prank(operator);
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.REMOVED,
                BaseLaunchpad.APPLICATION_STATUS.LAUNCHED
            )
        );
        vm.prank(curator);
        launchpad.claim(curationID); // Users have to call uncurate() to unlook vbio


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

        (BaseLaunchpad.APPLICATION_STATUS status_2, uint16 rewardProgramID_2, address program_2, address gov_2, uint128 totalStaked_2, address token_2) = launchpad.apps(0);
        assertEq(uint256(status_2), uint256(BaseLaunchpad.APPLICATION_STATUS.LAUNCHED));

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
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector, BaseLaunchpad.APPLICATION_STATUS.NULL, BaseLaunchpad.APPLICATION_STATUS.LAUNCHED));
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
        (BaseLaunchpad.APPLICATION_STATUS status, uint16 rewardProgramID, address program, address gov, uint128 totalStaked, address token) = launchpad.apps(0);
        assertEq(uint256(status), uint256(BaseLaunchpad.APPLICATION_STATUS.NULL));
        assertEq(rewardProgramID, 0);
        assertEq(program, address(0));
        assertEq(totalStaked, uint128(0));
        assertEq(gov, address(0));
        assertEq(token, address(0));
        
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.APPLICATION_STATUS status_2, uint16 rewardProgramID_2, address program_2, address gov_2, uint128 totalStaked_2, address token_2) = launchpad.apps(0);
        assertEq(uint256(status_2), uint256(BaseLaunchpad.APPLICATION_STATUS.SUBMITTED));
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
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(bioToken)));

        vm.prank(operator);
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.REJECTED,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(bioToken)));
        
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(1);

        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED
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
        (BaseLaunchpad.APPLICATION_STATUS status_0,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_0), uint256(BaseLaunchpad.APPLICATION_STATUS.SUBMITTED));
        (address token_0, address auction_0) = _accept(0);
        (BaseLaunchpad.APPLICATION_STATUS status_1,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_1), uint256(BaseLaunchpad.APPLICATION_STATUS.ACCEPTED));
        launchpad.graduate(0, xdao);
        (BaseLaunchpad.APPLICATION_STATUS status_2,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_2), uint256(BaseLaunchpad.APPLICATION_STATUS.COMPLETED));
        vm.stopPrank();
        vm.prank(xdao);
        launchpad.launch(0, _launchMetadata(address(bioToken)));
        (BaseLaunchpad.APPLICATION_STATUS status_3,,,,,) = launchpad.apps(0);
        assertEq(uint256(status_3), uint256(BaseLaunchpad.APPLICATION_STATUS.LAUNCHED));
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(BaseLaunchpad.MustClaimOnceLaunched.selector));
        launchpad.reject(0);

        //  reject a SUBMITTED project
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.APPLICATION_STATUS status_4,,,,,) = launchpad.apps(1);
        assertEq(uint256(status_4), uint256(BaseLaunchpad.APPLICATION_STATUS.SUBMITTED));
        launchpad.reject(1);
        (BaseLaunchpad.APPLICATION_STATUS status_5,,,,,) = launchpad.apps(1);
        assertEq(uint256(status_5), uint256(BaseLaunchpad.APPLICATION_STATUS.REJECTED));
        
        //  reject a ACCEPTED project
        launchpad.submit(operator, bytes32(0));
        (BaseLaunchpad.APPLICATION_STATUS status_6,,,,,) = launchpad.apps(2);
        assertEq(uint256(status_6), uint256(BaseLaunchpad.APPLICATION_STATUS.SUBMITTED));
        _accept(2);
        (BaseLaunchpad.APPLICATION_STATUS status_7,,,,,) = launchpad.apps(2);
        assertEq(uint256(status_7), uint256(BaseLaunchpad.APPLICATION_STATUS.ACCEPTED));
        launchpad.reject(2);
        (BaseLaunchpad.APPLICATION_STATUS status_8,,,,,) = launchpad.apps(2);
        assertEq(uint256(status_8), uint256(BaseLaunchpad.APPLICATION_STATUS.REMOVED));

        //  reject a COMPLETED project
        launchpad.submit(operator, bytes32(0));
        _accept(3);
        launchpad.graduate(3, xdao);
        (BaseLaunchpad.APPLICATION_STATUS status_9,,,,,) = launchpad.apps(3);
        assertEq(uint256(status_9), uint256(BaseLaunchpad.APPLICATION_STATUS.COMPLETED));
        launchpad.reject(3);
        (BaseLaunchpad.APPLICATION_STATUS status_10,,,,,) = launchpad.apps(3);
        assertEq(uint256(status_10), uint256(BaseLaunchpad.APPLICATION_STATUS.REMOVED));

        // rejecting a REJECTED/REMOVED project does nothing
        launchpad.submit(operator, bytes32(0));
        launchpad.reject(4);
        (BaseLaunchpad.APPLICATION_STATUS status_11,,,,,) = launchpad.apps(4);
        assertEq(uint256(status_11), uint256(BaseLaunchpad.APPLICATION_STATUS.REJECTED));
        launchpad.reject(4);
        launchpad.reject(4);
        (BaseLaunchpad.APPLICATION_STATUS status_12,,,,,) = launchpad.apps(4);
        assertEq(uint256(status_12), uint256(BaseLaunchpad.APPLICATION_STATUS.REJECTED));

        launchpad.submit(operator, bytes32(0));
        _accept(5);
        launchpad.reject(5);
        (BaseLaunchpad.APPLICATION_STATUS status_13,,,,,) = launchpad.apps(5);
        assertEq(uint256(status_13), uint256(BaseLaunchpad.APPLICATION_STATUS.REMOVED));
        launchpad.reject(5);
        (BaseLaunchpad.APPLICATION_STATUS status_14,,,,,) = launchpad.apps(5);
        assertEq(uint256(status_14), uint256(BaseLaunchpad.APPLICATION_STATUS.REMOVED));

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

    function test_accept_reservesXdaoTokenBasedOnProgram() public {
        launchpad.submit(operator, bytes32(0));

        vm.prank(operator);
        (address token, address auction) = _accept(0);

        (BaseLaunchpad.APPLICATION_STATUS status_2, uint16 rewardProgramID_2, address program_2, address gov_2, uint128 totalStaked_2, address token_2) = launchpad.apps(0);
        assertEq(token, token_2);

        (uint128 liqReserves, uint128 curatorReserves) = launchpad.rewards(0);

        (uint16 totalReserveRate, uint16 liqReserveRate, uint16 curatorReserveRate) = launchpad.pRewards(operator, 0);

        assertEq(totalReserveRate, uint256(liqReserveRate) + uint256(curatorReserveRate));
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

    // function test_accept_mustMintReservesToLaunchpad() public {
    //     launchpad.submit(operator, bytes32(0));
    //     vm.prank(operator);
    //     (address token_0, address auction_0) = _accept(0);

    //     (uint128 liqReserves, uint128 curatorReserves) = launchpad.rewards(0);
    //     assertGt(XDAOToken(token_0).balanceOf(address(launchpad)), uint256(liqReserves) + uint256(curatorReserves));
    // }


    function test_accept_mustDeployNewToken() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);

        assertNotEq(token, address(0));
    }

    function test_accept_mustDeployCuratorAuction() public {
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        (address token, address auction) = _accept(0);

        // TODO ideally do this by sniffing call data to auction contract, parsing as AuctionMetadata, and reading the values
        // check standardized params
        // 1 week with 1 day future offset
        // in new xDAO Token
        // curatorLaunchCode
        // new xdao governance address

        assertNotEq(auction, address(0));
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
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED
            )
        );
        launchpad.graduate(0, xdao);
        
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.REJECTED,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED
            )
        );
        launchpad.graduate(0, xdao);


        launchpad.submit(operator, bytes32(0));
        _accept(1);
        launchpad.graduate(1, xdao);

        // cant graduate once graudated already
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED
            )
        );
        launchpad.graduate(1, xdao);
        vm.stopPrank();
    }

    function _launchMetadata(address token) internal returns (BaseLaunchpad.AuctionMetadata memory) {
        bytes[] memory customLaunchData;
        return BaseLaunchpad.AuctionMetadata({
            launchCode: curatorAuction,
            manager: bioNetwork,
            amount: 0,
            token: token,
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        });
    }

    function _launchMetadata(address token, address launchCode, bytes[] memory customLaunchData) internal returns (BaseLaunchpad.AuctionMetadata memory) {
        return BaseLaunchpad.AuctionMetadata({
            launchCode: launchCode,
            manager: bioNetwork,
            amount: 0,
            token: token,
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        });
    }

    function _accept(uint96 id) internal returns(address token, address auction) {
        return launchpad.accept(id, BaseLaunchpad.BorgMetadata({
            name: "test",
            symbol: "tester",
            maxSupply: 1_000_000 ether
        }));
    }

}