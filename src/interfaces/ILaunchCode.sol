// called during Launch(). 
// Gives standard inputs with one custom field for data for launchcode
// validate data going in
// only for public launch. staker launch is automated in launchpad
import { Utils } from "src/Utils.sol";

interface ILaunchFactory {
    function launch(Utils.AuctionMetadata calldata meta) external returns(address);
    function initialize(address launchpad, address launchImpl, address vestingImpl) external;
}

interface ILaunchCode {
    // standard metadata on auction
    function getAuctionData() external view returns(uint32 startTime, uint32 endTime,  address wantToken, uint256 wantAmount, address giveToken, uint256 giveAmount);
    function vestingContract() external returns(address); // TODO decide btw one of these api. Just address has more use, no one should need vestLength tho
    function vesting() external returns(address, uint32);
    function manager() external returns(address);
    
    function sellToken() external returns(address);
    function buyToken() external returns(address);
    function totalBuyAmount() external returns(uint256);
    function totalSellAmount() external returns(uint128);

    // function getAuctionMetadata() external view returns(address vesting, uint256 vestingLength);
    function initialize(address launchpad, Utils.AuctionMetadata calldata meta) external;
    function claim(uint256 curationID, uint256 staked) external;
    function sweep(address claimer, uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claw(uint256 amount) external;
    function reward(address claimer, uint256 staked) external returns(uint256, uint256);
    // check if custom launch template data is valid
    // function validateData(bytes[] calldata inputs) external;

    event Claim(address indexed claimer, uint256 received, uint256 paid);

    error AlreadyInitialized();
    error InvalidVestingAddress();
    error InvalidTokenAddress();
    error InvalidManagerAddress();
    error InvalidTokenBalance();
    error InvalidLaunchpad();
    error InvalidStartTime();
    error InvalidEndTime();
    error InvalidAmount();
    error InvalidVestLength();
    

    error NotOpen();
    error NotGovernance();

    error NotClaimer();
    error ClaimTransferFailed();
    error ClaimPeriodNotOver();
}

interface ITPA is ILaunchCode {
    function totalProRataShares() external returns(uint128);
}