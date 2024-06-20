import { Clones } from  "@openzeppelin/contracts/proxy/Clones.sol";

import { ILaunchCode } from "../interfaces/ILaunchCode.sol";

// // we set the valuation

interface ILaunchpad {
    mapping(uint256 => uint255) public curations;
}
// // specific % of xDAO token for sale (5%)
// // store amount of token per bioDAO `sales.[appID]
// // minimum $200k for sale to complete, max $1M
// // offered OTC to curators pro-rata BIO staked 
// // unclaimed xDAO tokens sent to treasury (or rolled into public auction)
// // Hve time deadline. If not complete by deadline, any BIO holder (>100,000) can purchase tokens
// // once sale complete then claimable by purchasers

contract LaunchCodeFactory {
    ILaunchpad launchpad;
    ILaunchCode launchImpl;
    address vestingImpl;
    address wantToken;

    constructor(address launchpad_, address launchImpl_, address vestingImpl_, address wantToken_) {
        launchpad = launchpad_;
        launchImpl = launchImpl_;
        vestingImpl = vestingImpl_;
        wantToken = wantToken_;
    }

    ///@notice  One of 2 function delegatecall'ed by Launchpad, rest are normal contract interactions
    /// @dev Doest require contract to be initialized
    function launch(BioLib.AuctionMetadata memory meta) external returns(address proxy) {
        vesting = address(Clones.clone(vestingImpl));
        proxy = address(Clones.clone(launchImpl));
        XDAOToken(meta.giveToken).transfer(proxy, meta.totalGive);
        meta.wantToken = wantToken;
        meta.totalWant = 
        ILaunchCode(auction).initialize(address(launchpad), vesting, meta);
        // TODO emit clone event
    }
}

contract ProRata is ILaunchCode {
    uint128 totalGive;
    uint128 totalProRataShares;
    uint256 totalWant;
    uint32 startTime;
    uint32 endTime;
    uint32 vestingLength;
    XDAOToken giveToken;
    XDAOToken wantToken;
    address governance;
    ILaunchpad launchpad;
    uint128 currentGive;
    uint128 claimableWant;
    address vesting;

    function initialize(
        address launchpad,
        address vesting_,
        BIOLib.AuctionMetadata calldata meta
    ) public {
        if(meta.giveToken != address(0)) revert AlreadyInitialized();
        if(meta.giveToken == address(0)) revert InvalidTokenAddress();
        if(XDAOTOken(meta.token).balanceOf(address(this)) < meta.totalGive) revert InvalidTokenBalance();
        if(launchpad == address(0)) revert InvalidLaunchpad();
        if(meta.startTime < block.timestamp) revert InvalidStartTime();
        if(meta.startTime > endTime) revert InvalidEndTime();

        vesting = vesting_;
        giveToken = XDAOToken(meta.giveToken);
        totalGive = meta.totalGive;
        startTime = meta.startTime;
        endTime = meta.endTime;
        wantToken = meta.wantToken;
        totalWant = meta.totalWant;
        launchpad = ILaunchpad(launchpad);
        (totalProRataShares, vestingLength) = abi.decode(meta.customLaunchData, (uint256, uint32));
    }


    function validateData(bytes[] calldata inputs) external {

    }


    /// @dev contract MUST BE initialized
    function claim(address claimer, uint128 totalStaked) public {
        if(msg.sender != address(launchpad)) revert NotLaunchpad();
        _claim(totalStaked * totalGive / totalProRataShares, totalStaked * totalWant / totalProRataShares);
    }

    function sweep(address claimer, uint128 purchased) public {
        if(block.timestamp < endTime) revert NotOpen();
        // TODO require some BIO lock/burn/payment?

        _claim(purchased, purchased * totalWant / totalGive);
    }

    function _claim(uint256 tokensClaimed, uint256 tokensPaid) internal {
        currentGive -= tokensClaimed;
        claimableWant += tokensPaid;

        XDAOToken(wantToken).transferFrom(claimer, address(this), tokensPaid);
        // TODO transfer to esting contract
        if(!giveToken.transfer(claimer, tokensClaimed)) revert ClaimTransferFailed();  // TODO safeTransfer
    }

    function withdraw(address claimer, uint128 purchased) public {
        if(block.timestamp < endTime) revert NotOpen();

        _claim(purchased, purchased * totalWant / totalGive);
    }

}