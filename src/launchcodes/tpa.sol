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

    event FactoryClone(address token, uint256 amount);
    event FactoryClone(Utils.AuctionMetadata meta);

    function initialize(address launchpad_, address launchImpl_, address vestingImpl_)  external {
        _launchpad = launchpad_;
        _launchImpl = launchImpl_;
        _vestingImpl = vestingImpl_;
    }

    function launch(Utils.AuctionMetadata memory meta) external returns(address proxy) {
        // ITokenVesting _vestingContract = ITokenVesting(Clones.clone(_vestingImpl));
        proxy = address(Clones.clone(_launchImpl));

        emit FactoryClone(meta);
        // emit FactoryClone(meta.giveToken, XDAOToken(meta.giveToken).balanceOf(address(this)));

        XDAOToken(meta.giveToken).transfer(proxy, meta.totalGive); // TODO safeTransfer

        // if error revert InsufficientTokensForAuction()
        // _vestingContract.grantRole(_VESTING_ROLE, proxy);

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
    uint32 internal _vestingLength;
    XDAOToken public giveToken;
    XDAOToken public wantToken;
    address public manager;
    ILaunchpad public launchpad;
    ITokenVesting internal _vestingContract;

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
        (totalProRataShares, vesting_, _vestingLength) = abi.decode(meta.customLaunchData, (uint128, address, uint32));

        if(address(giveToken) != address(0)) revert AlreadyInitialized();
        if(meta.giveToken == address(0)) revert InvalidTokenAddress();
        if(vesting_ == address(0)) revert InvalidVestingAddress();
        if(launchpad_ == address(0)) revert InvalidLaunchpad();
        if(meta.totalGive == 0) revert InvalidAmount();
        if(meta.manager == address(0)) revert InvalidManagerAddress();
        if(meta.startTime > meta.endTime) revert InvalidEndTime();
        if(meta.startTime < block.timestamp) revert InvalidStartTime();
        if(XDAOToken(meta.giveToken).balanceOf(address(this)) < meta.totalGive) revert InvalidTokenBalance();

        _vestingContract = ITokenVesting(vesting_);
        giveToken = XDAOToken(meta.giveToken);
        totalGive = meta.totalGive;
        startTime = meta.startTime;
        endTime = meta.endTime;
        wantToken = XDAOToken(meta.wantToken);
        totalWant = meta.totalWant;
        launchpad = ILaunchpad(launchpad_);
        manager = meta.manager;
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

    function vestingContract() public view returns(address) {
        return address(_vestingContract);
    }

    function vesting() public view returns(address, uint32) {
        return (address(_vestingContract), _vestingLength);
    }
    function auctionToken() external returns(address) {
        return address(giveToken);
    }

    function totalAuctionable() external returns(uint128) {
        return totalGive;
    }

    function purchaseToken() external returns(address) {
        return address(wantToken);
    }

    function totalPurchasable() external returns(uint256) {
        return totalWant;
    }



    function claimableWant() public view returns(uint256) {
        return XDAOToken(wantToken).balanceOf(address(this));
    }

    function remainingGive() public view returns(uint256) {
        return XDAOToken(giveToken).balanceOf(address(this));
    }

    function _assertManager() internal {
        if(msg.sender != manager) revert NotGovernance();
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

    function _claim(address claimer, uint256 giveAmount, uint256 wantAmount) internal {
        // TODO safeTransfer on both
        XDAOToken(wantToken).transferFrom(claimer, address(this), wantAmount);

        if(!giveToken.transfer(address(_vestingContract), giveAmount)) revert ClaimTransferFailed();
        _vestingContract.createVestingSchedule(claimer, endTime, 365 days, _vestingLength, 86400, false, giveAmount);

        // dont track claimable want token, manager can claim all.

        emit Claim(claimer, giveAmount, wantAmount);
    }


    function withdraw(uint256 amount) public {
        _assertHasEnded();
        _assertManager();

        XDAOToken(wantToken).transfer(manager, amount); // TODO safeTransfer 
    }

    function claw(uint256 amount) public {
        _assertManager();
        if(block.timestamp <= endTime + _CLAIM_PERIOD_LENGTH) revert ClaimPeriodNotOver();

        XDAOToken(giveToken).transfer(manager, amount); // TODO safeTransfer 
    }

}