import { BaseLaunchpad } from "src/BaseLaunchpad.sol";
import { BaseLaunchpadTest } from "./Base.t.sol";


contract BasicLaunchpadTests is BaseLaunchpadTest {

    function setUp() public virtual override(BaseLaunchpadTest) {
        super.setUp();
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

    function  test_launch_statusMustBeCOMPLETED() public {
        bytes[] memory customLaunchData;
        address launchCode = curatorAuction;
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.SUBMITTED,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(0, BaseLaunchpad.AuctionMetadata({
            launchCode: launchCode,
            manager: bioNetwork,
            amount: 0,
            token: address(bioToken),
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        }));

        emit log_named_bytes32("post launch #1", bytes32(0));
        vm.prank(operator);
        launchpad.reject(0);
        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.REJECTED,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(0, BaseLaunchpad.AuctionMetadata({
            launchCode: launchCode,
            manager: bioNetwork,
            amount: 0,
            token: address(bioToken),
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        }));
        
        emit log_named_bytes32("post launch #2", bytes32(0));
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        address token = launchpad.accept(1, BaseLaunchpad.BorgMetadata({
            name: "test",
            symbol: "tester",
            maxSupply: 1_000_000 ether
        }));

        vm.expectRevert(
            abi.encodeWithSelector(BaseLaunchpad.InvalidAppStatus.selector,
                BaseLaunchpad.APPLICATION_STATUS.ACCEPTED,
                BaseLaunchpad.APPLICATION_STATUS.COMPLETED
            )
        );
        vm.prank(xdao);
        launchpad.launch(1, BaseLaunchpad.AuctionMetadata({
            launchCode: launchCode,
            manager: bioNetwork,
            amount: 0,
            token: token,
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        }));
        emit log_named_bytes32("post launch #3", bytes32(0));

        /** Can finally launch() once marked completed on graduate() */
        vm.prank(operator);
        launchpad.graduate(1, xdao);

        vm.prank(xdao);
        launchpad.launch(1, BaseLaunchpad.AuctionMetadata({
            launchCode: launchCode,
            manager: bioNetwork,
            amount: 0,
            token: token,
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1),
            customLaunchData: customLaunchData
        }));

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


}