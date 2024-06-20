import { XDAOToken } from "./XDAOToken.sol";

abstract contract BaseLaunchpad {
    enum APPLICATION_STATUS { NULL, SUBMITTED, ACCEPTED, REJECTED, COMPLETED, REMOVED, LAUNCHED }
    // slot 0
    uint16 constant BPS_COEFFICIENT = 10_000; // xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_LIQUIDITY_RESERVES_BPS = 1_000; // 10% -  xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_OPERATOR_REWARD_BPS = 8_000; // 80% - max 80% of a token can go org running a cohort. namely bioDAOs for their IPTs
    uint16 constant MAX_CURATOR_REWARDS_RESERVE_BPS = 100; // 1% - xDAO tokens reserved for Curators to applicants
    uint16 constant MAX_CURATOR_AUCTION_RESERVE_BPS = 2_090; // 20% - xDAO tokens reserved for Curators to applicants
    XDAOToken public BIO = XDAOToken(address(0xB10));
    // slot 1
    XDAOToken public VBIO = XDAOToken(address(0xB10));
    XDAOToken public USDC = XDAOToken(address(0x05D));
    uint96 public nextApplicantId; // global applicant ID pool
    // slot 2
    address public owner; // BIO Network governance manager
    uint96 public operatorBIOReward; // BIO per launch() in a program. TODO should be pro-rata curator reward too?
    // slot 3
    address public bioBank; // BIO Network liquidity manager
    // uint96 curatorBIOReward; // BIO per 10,000 BIO staked e.g. 10 / BPS_COEFFICIENT. Positions < 10,000 wont get curation rewards
    // slot 4
    address public curatorLaunchCode = address(0x0); // default launch code for private curator auctions on accept()

    // bioDAOs. ID = uint64 to encode with curator address into uint256
    mapping(uint96 => Application) public apps; // bioDAO entry in launchpad registry
    mapping(uint96 => AppRewards) public rewards; // how much of bioDAO token go to curators and liquidity after launch
    mapping(address => mapping(uint16 => ProgramRewards)) public pRewards;
    
    // curators
    mapping(uint256 => uint256) public curations; // curator stakes to individual applicants
    mapping(address => uint256) public vbioLocked; // (how much vested BIO someone has staked already)
    // BIO gov
    mapping(address =>  Program) public programs;// programId -> rewardNonce -> reward rates across bioDAOs in program
    mapping(address =>  bool) public launchCodes;// approved templatized token sale strategies for bioDAOs to use

    // Launchpad Usage Events
    event SetApplicantStatus(uint96 indexed applicant, APPLICATION_STATUS indexed oldStatus, APPLICATION_STATUS indexed newStatus);
    event SubmitApp(address indexed program, uint96 applicantID, bytes32 ipfsHash);
    event Curate(uint96 indexed applicant, address indexed curator, uint256 amount, uint256 curationID);
    event Uncurate(uint256 indexed curationID);
    event Claim(uint256 indexed curationId, uint256 xdaoAmount);
    event Launch(uint96 indexed applicant,  address token, uint256 curatorAuctionReserves, uint256 liquidityReserves);
    event StartAuction(uint96 indexed applicant, address auction, uint256 amount, uint32 startDate, uint32 endDate);

    // Launchpad Admin Events
    event SetProgram(address indexed program, bool approval);
    event SetReactor(address indexed program);
    event SetLaunchCodes(address indexed executor, bool isAllowed);
    event SetProgramRewards(address indexed program, uint16 rewardId, ProgramRewards rewards);

    struct ProgramRewards {
        uint16 totalRewardsBps; // sum of all program rewards in bioDAO tokens for checking overflows during launch()
        uint16 liquidityReserves;//  (e.g. 10% = 1000)
        uint16 curatorAuction; // (e.g. 0.5% = 50) // TODO remove bc standardized?
    }

    struct Program {
        address stakingToken;
        uint16 nextRewardId;
    }

    struct Application {
        // slot 1
        APPLICATION_STATUS status;
        uint16 rewardProgramID; // rewards at time of accepted (not applied)
        address program;
        // slot 2
        address governance;
        uint128 totalStaked;
        // slot 3
        address token;
    }

    struct AppRewards {
        uint128 totalLiquidityReserves; // (in xDAO token, w/ xDAO token decimals)
        uint128 totalCuratorAuction; // (in xDAO token, w/xDAO token decimals)
    }

    struct OrgMetadata {
        uint128 valuation; // 8 decimal usdc valuation
        uint256 maxSupply; // total max supply of new xDAO token
        string name; // token name
        string symbol; // token symbol
    }

    struct AuctionMetadata {
        address launchCode; // approved template for fair token sales by BIO network 
        address giveToken;  // token being launched
        uint128 totalGive; // initial xDAO treasury (excl BIO reserves annd rewards)
        uint128 totalWantReceived;
        address wantToken;
        uint32  startTime; // unix timestamp or block depending on launchCode
        uint32  endTime; // unix timestamp or block depending on launchCode
        address manager; // who can update/close/etc auction after launch
        bytes[] customLaunchData; // (for launch provider if needed for auction settings or something)
    }


    error NotOwner();
    error NotProgramOperator();
    error NotBioBank();
    error NotCurator();
    error NotApplicationOwner();

    error InvalidAppStatus(APPLICATION_STATUS current, APPLICATION_STATUS target);
    error TakeoffFailed();

    error BadLaunchCode();
    error NotCuratorLaunchCode();
    error InvalidOwnerShare();
    error InvalidTokenSupply();
    error InvalidProgramRewards_LR();
    error InvalidProgramRewards_OR();
    error InvalidProgramRewards_CR();
    error InvalidProgramRewards_CA();

    error MustStakeOver0BIO();
    error InsufficientVbioBalance();
    error InsufficientBioBalance();
    error OverdrawnVbio();
    error RewardsAlreadyClaimed();
    error MustClaimOnceLaunched();
}