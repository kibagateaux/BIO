import "forge/std";

contract BasicLaunchpadTests is Test {

    setup() {

    };

    /*
        bioDAO actions
    */

    prove_submit_applicantID_increments(uint8 applicants) public {
        for(uint i; i < applicants; i++) {
            assertEq(launchpad.nextApplicantId(), i);
            launchpad.submit(operator, bytes32(0));
        }
    }

    prove_launch_statusMustBeCOMPLETED() public {
        launchpad.submit(operator, bytes32(0));
        vm.expectRevert(launchpad.InvalidAppStatus.selector, launchpad.APPLICATION_STATUS.SUBMITTED, launchpad.APPLICATION_STATUS.COMPLETED);

        vm.prank(address(0xb10da0));
        launchpad.launch();

        vm.prank(operator);
        launchpad.reject(0);

        vm.expectRevert(launchpad.InvalidAppStatus.selector, launchpad.APPLICATION_STATUS.REJECTED, launchpad.APPLICATION_STATUS.COMPLETED);
        
        vm.prank(address(0xb10da0));
        launchpad.launch();
        
        launchpad.submit(operator, bytes32(0));
        vm.prank(operator);
        address token = launchpad.accept(1);

        vm.prank(address(0xb10da0));
        bytes[] customLaunchData = [];
        launchpad.launch(1, AuctionMetadata({
            amount: 0,
            token: token,
            startTime: block.timestamp,
            endTime: block.timestamp + 1,
            customLaunchData: customLaunchData
        }));
    }

    // u would think right? But no! bc of scientist onboarding no address at time of application, proxies submit on their behalf.
    // prove_submit_applicant_cant_reapply() public {
    //     vm.prank();
    //     launchpad.submit();

    //     vm.expectRevert(BaseLaunchpad.)

    // }


    prove_submit_applicant_cant_reapply() public {
        vm.prank();
        launchpad.submit();

        vm.expectRevert(BaseLaunchpad.)
    }



}