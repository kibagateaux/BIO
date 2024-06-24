pragma solidity ^0.8.23;

import "forge-std/console.sol";

import { Clones } from  "@openzeppelin/contracts/proxy/Clones.sol";

import { ILaunchCode, ILaunchFactory } from "../interfaces/ILaunchCode.sol";
import { ITokenVesting } from "../interfaces/ITokenVesting.sol";
import { Utils } from "../Utils.sol";
import { XDAOToken } from "../XDAOToken.sol";

interface ILaunchpad {
    function curations(uint256 curationID) external returns(uint256);
    function _decodeID(uint256 curationID) external returns (uint96 appID, address curator);
}

// // specific % of xDAO token for sale (5%)
// // store amount of token per bioDAO `sales.[appID]
// // minimum $200k for sale to complete, max $1M
// // offered OTC to curators pro-rata BIO staked 
// // unclaimed xDAO tokens sent to treasury (or rolled into public auction)
// // Hve time deadline. If not complete by deadline, any BIO holder (>100,000) can purchase tokens
// // once sale complete then claimable by purchasers

contract LaunchCodeFactory is ILaunchFactory {
    bytes32 private constant _VESTING_ROLE = keccak256("VESTING_CREATOR_ROLE"); // see TokenVesting.sol
    bytes32 private constant _ADMIN_ROLE = bytes32(0x00); // see OZ AccessRoles.sol

    address _launchpad;
    address _launchImpl;
    address _vestingImpl;

    function initialize(address launchpad_, address launchImpl_, address vestingImpl_)  external {
        _launchpad = launchpad_;
        _launchImpl = launchImpl_;
        _vestingImpl = vestingImpl_;
    }

    function launch(Utils.AuctionMetadata calldata meta) external returns(address proxy) {
        // ITokenVesting vesting = ITokenVesting(Clones.clone(_vestingImpl));
        proxy = address(Clones.clone(_launchImpl));

        XDAOToken(meta.giveToken).transfer(proxy, meta.totalGive); // TODO safeTransfer
        // if error revert InsufficientTokensForAuction()
        // vesting.grantRole(_VESTING_ROLE, proxy);

        ILaunchCode(proxy).initialize(_launchpad, meta);
    }

    /** All creating new factory for new launch codes automatically */
    function createFactory(address launchcode) external returns (address) {
        ILaunchFactory launchFactory = ILaunchFactory(Clones.clone(address(this)));
        launchFactory.initialize(_launchpad, launchcode, _vestingImpl);
        return address(launchFactory);
    }
}

contract ProRata is ILaunchCode {
    uint32 private constant _CLAIM_PERIOD_LENGTH = 7 days;
    uint128 public totalGive;
    uint128 public totalProRataShares;
    uint256 public totalWant;
    uint32 public startTime;
    uint32 public endTime;
    uint32 public vestingLength;
    XDAOToken public giveToken;
    XDAOToken public wantToken;
    address public governance;
    ILaunchpad public launchpad;
    ITokenVesting public vesting;

    function initialize(
        address launchpad_,
        Utils.AuctionMetadata calldata meta
    ) public {
        console.log("TPA contract: startTime --", meta.startTime);
        console.log("TPA contract: giveToken --", meta.giveToken);
        console.log("TPA contract: totalGive --", meta.totalGive);
        console.log("TPA contract: wantToken --", meta.wantToken);
        console.log("TPA contract: manager --", meta.manager);
        address vesting_;
        (totalProRataShares, vesting_, vestingLength) = abi.decode(meta.customLaunchData, (uint128, address, uint32));

        if(meta.totalGive == 0) revert InvalidAmount();
        if(vesting_ != address(0)) revert InvalidVestingAddress();
        if(meta.giveToken != address(0)) revert AlreadyInitialized();
        if(meta.giveToken == address(0)) revert InvalidTokenAddress();
        if(XDAOToken(meta.giveToken).balanceOf(address(this)) < meta.totalGive) revert InvalidTokenBalance();
        if(launchpad_ == address(0)) revert InvalidLaunchpad();
        if(meta.startTime < block.timestamp) revert InvalidStartTime();
        if(meta.startTime > endTime) revert InvalidEndTime();

        vesting = ITokenVesting(vesting_);
        giveToken = XDAOToken(meta.giveToken);
        totalGive = meta.totalGive;
        startTime = meta.startTime;
        endTime = meta.endTime;
        wantToken = XDAOToken(meta.wantToken);
        totalWant = meta.totalWant;
        launchpad = ILaunchpad(launchpad_);
    }

    function getAuctionData() external view returns(uint32, uint32,  address, uint256, address, uint256) {
        return (
            startTime,
            endTime,
            address(wantToken),
            uint256(totalWant),
            address(giveToken),
            uint256(totalGive)
        );
    }

    function claimableWant() public view returns(uint256) {
        return XDAOToken(wantToken).balanceOf(address(this));
    }

    function remainingGive() public view returns(uint256) {
        return XDAOToken(giveToken).balanceOf(address(this));
    }

    function _assertGovernance() internal {
        if(msg.sender != governance) revert NotGovernance();
    }

    function _assertHasEnded() internal {
        if(block.timestamp < endTime) revert NotOpen();
    }

    function _assertHasStarted() internal {
        if(block.timestamp > startTime) revert NotOpen();
    }

    function reward(address claimer, uint256 staked) public view returns(uint256 received, uint256 owed) {
        return (staked * uint256(totalGive) / totalProRataShares, staked * uint256(totalWant) / totalProRataShares);
    }

    /// @dev contract MUST BE initialized
    function claim(uint256 curationID, uint256 staked) public {
        _assertHasStarted();
        // how would this work for LaunchCodes that arent based on staking amounts e.g. post-launch auction?
        (,address curator) = launchpad._decodeID(curationID); // TODO move encode/decode to lib. 
        // if(msg.sender != curator) revert NotClaimer(); // TODO depends on pattern we want. pushing logic to launchcodes means w e can hve this controleld by launchpad directly and others can be claimed independently
        if(msg.sender != address(launchpad)) revert NotClaimer();
        (uint256 received, uint256 owed) = reward(curator, staked);
        _claim(curator, received, owed);
    }

    function sweep(address claimer, uint256 amount) public {
        _assertHasEnded();
        // TODO require some BIO lock/burn/payment?

        _claim(claimer, amount, amount * uint256(totalWant) / uint256(totalGive));
    }

    function _claim(address claimer, uint256 tokensClaimed, uint256 tokensPaid) internal {
        // TODO safeTransfer on both
        XDAOToken(wantToken).transferFrom(claimer, address(this), tokensPaid);
        if(!giveToken.transfer(address(vesting), tokensClaimed)) revert ClaimTransferFailed();
        vesting.createVestingSchedule(claimer, endTime, 365 days, vestingLength, 86400, false, tokensClaimed);
    }


    function withdraw(uint256 amount) public {
        _assertHasEnded();
        _assertGovernance();

        XDAOToken(wantToken).transfer(governance, amount); // TODO safeTransfer 
    }

    function claw(uint256 amount) public {
        _assertGovernance();
        if(block.timestamp <= endTime + _CLAIM_PERIOD_LENGTH) revert ClaimPeriodNotOver();

        XDAOToken(giveToken).transfer(governance, amount); // TODO safeTransfer 
    }

}