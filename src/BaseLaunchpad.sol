abstract contract BaseLaunchpad {
    enum APPLICATION_STATUS { SUBMITTED, ACCEPTED, REJECTED, COMPLETED, REMOVED, LAUNCHED }
    // slot 0
    uint16 constant BPS_COEFFICIENT = 10_000; // xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_LIQUIDITY_RESERVES_BPS = 1_000; // 10% -  xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_OPERATOR_REWARD_BPS = 8_000; // 80% - max 80% of a token can go org running a cohort. namely bioDAOs for their IPTs
    uint16 constant MAX_CURATOR_REWARDS_RESERVE_BPS = 100; // 1% - xDAO tokens reserved for Curators to applicants
    uint16 constant MAX_CURATOR_AUCTION_RESERVE_BPS = 2_090; // 20% - xDAO tokens reserved for Curators to applicants
    address constant BIO = address(0xB10);
    // slot 1
    address constant VBIO = address(0xB10);
    uint96 nextApplicantId; // global applicant ID pool
    // slot 2
    address owner; // BIO Network governance manager
    uint96 operatorBIOReward; // BIO per launch() in a program
    // slot 3
    address bioReactor; // BIO Network liquidity manager
    // uint96 curatorBIOReward; // BIO per launch() staked in
    // slot 4
    address curatorLaunchCode = address(0x0); // default launch code for private curator auctions on accept()

    // bioDAOs. ID = uint64 to encode with curator address into uint256
    mapping(uint64 => Application) apps; // bioDAO entry in launchpad registry
    mapping(uint64 => AppRewards) rewards; // how much of bioDAO token go to curators and liquidity after launch
    // curators
    mapping(uint256 => uint256) curations; // curator stakes to individual applicants
    mapping(address => uint256) vbioLocked; // (how much vested BIO someone has staked already)
    // BIO gov
    mapping(address =>  Program) programs;// programId -> rewardNonce -> reward rates across bioDAOs in program
    mapping(address =>  bool) launchCodes;// approved templatized token sale strategies for bioDAOs to use

    // Launchpad Usage Events
    event SubmitApp(address indexed program, uint64 applicantID, bytes32 ipfsHash);
    event Curate(uint64 indexed applicant, address indexed curator, uint256 amount, uint256 curationID);
    event Uncurate(uint256 indexed curationID);
    event Claim(uint256 indexed curationId, uint256 xdaoAmount);
    event Launch(uint64 applicant,  address token, uint256 initSupply, uint256 liquidityReserves);
    event StartAuction(uint64 indexed applicant,  uint256 initSupply, uint32 startDate, uint32 endDate);

    // Launchpad Admin Events
    event SetProgram(address indexed program, bool approval);
    event SetReactor(address indexed program);
    event SetLaunchCodes(address indexed executor, bool isAllowed);
    event SetProgramRewards(address indexed program, ProgramRewards rewards);

    struct ProgramRewards {
        uint16 totalRewardsBps; // sum of all program rewards in bioDAO tokens for checking overflows during launch()
        uint16 liquidityReserves;//  (e.g. 10% = 1000)
        uint16 curatorAuction; // (e.g. 0.5% = 50) // TODO remove bc standardized?
    }

    struct Program {
        address stakingToken;
        uint16 nextRewardId;
        mapping(uint16 => ProgramRewards) pRewards;
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

    struct BorgMetadata {
        uint256 maxSupply; // total max supply of new xDAO token
        string name; // token name
        string symbol; // token symbol
    }

    struct AuctionMetadata {
        address launchCode; // approved template for fair token sales by BIO network 
        address token;  // token being launched
        address manager; // who can update/close/etc auction after launch
        uint128 amount; // initial xDAO treasury (excl BIO reserves annd rewards)
        uint32  startTime; // unix timestamp or block depending on launchCode
        uint32  endTime; // unix timestamp or block depending on launchCode
        bytes[] customLaunchData; // (for launch provider if needed for auction settings or something)
    }


    error NotOwner();
    error NotProgramOperator();
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

    error InsufficientVbioBalance();
    error InsufficientBioBalance();
    error OverdrawnVbio();
    error RewardsAlreadyClaimed();
    error MustClaimOnceLaunched();
}