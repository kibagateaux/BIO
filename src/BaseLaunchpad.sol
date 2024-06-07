abstract contract BaseLaunchpad {
    enum APPLICATION_STATUS { SUBMITTED, ACCEPTED, REJECTED, COMPLETED, REMOVED, LAUNCHED }
    // slot 0
    uint16 constant BPS_COEFFICIENT = 10_000; // xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_LIQUIDITY_RESERVES_BPS = 420; // xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_OPERATOR_REWARD_BPS = 8000; // max 80% of a token can go org running a cohort. namely bioDAOs for their IPTs
    uint16 constant MAX_CURATOR_REWARDS_RESERVE_BPS = 100; // xDAO tokens reserved for Curators to applicants
    uint16 constant MAX_CURATOR_AUCTION_RESERVE_BPS = 590; // xDAO tokens reserved for Curators to applicants
    address constant BIO = address(0xB10);

    // slot 1
    address constant VBIO = address(0xB10);

    // slot 2
    address governance; // BIO Network governance manager
    uint96 operatorBIOReward; // BIO per launch() in a program
    
    // slot 3
    address bioReactor; // BIO Network liquidity manager
    uint96 curatorBIOReward; // BIO per launch() staked in

    mapping(address => uint256) vbioLocked; // (how much vested BIO someone has staked already)
    mapping(uint64 => Application) apps; // bioDAO entry in launchpad
    mapping(uint64 => AppRewards) rewards; // bioDAO entry in launchpad
    mapping(uint256 => Curation) curations; // bioDAO entry in launchpad
    mapping(address =>  Program) programs;// programId  → rewardNonce → reward rates across bioDAOs in program
    mapping(address =>  string) launchCodes;// templatize GTM playbooks for bioDAOs. launchcode => expectedFuncSignature?
    

    struct ProgramRewards {
        // all bps of bioDAO token to distribute to each pool.
        uint16 liquidityReserves;//  (e.g. 4% = 400)
        uint16 operatorReward; // (e.g. 2% = 200)
        uint16 curatorReward; // (e.g. 0.5% = 50)
        uint16 curatorAuction; // (e.g. 0.5% = 50)
    }

    struct Program {
        // address programID = provider
        uint16 nextRewardId;
        uint16 totalRewardsReserved;
        address stakingToken;
        mapping(uint16 =>  ProgramRewards) pRewards;
    }

    struct Application {
        // uint64 appID = unit64(uint32 programId, uint32 nonce)
        
        // slot 1
        APPLICATION_STATUS status;
        uint16 founderRewardBps; // how many tokens go to founding team at launch()
        address governance;
        // slot 2
        uint16 rewardProgramID; // rewards at time of accepted (not applied)
        uint128 totalStaked;
    }

    struct AppRewards {
        address token;
        // uint64 appID = unit64(uint32 programId, uint16 nonce)
        uint128 totalLiquidityReserves; // (in xDAO token, w/ xDAO token decimals)
        uint128 totalOperatorRewards; // (in xDAO token, w/ xDAO token decimals)
        uint128 totalCuratorRewards; // (in xDAO token, w/ xDAO token decimals)
        uint128 totalCuratorAuction; // (in xDAO token, w/xDAO token decimals)
    }

    struct Curation {
        // uint256 *stakeID* = unit256(uint64 appID, uint64 stake)
        address currentOwner;
        uint96 amount;
        bool isVbio;
    }

    struct LaunchMetadata {
        string name; // token name
        string symbol; // token symbol
        uint256 maxSupply;
        uint256 initialSupply;
        uint32 startDate; // public auction start date
        uint32 endDate; // public auction end date
        bytes[] customLaunchData; // (for launch provider if needed for auction settings or something)
    }


    error NotBIOGovernor();
    error NotProgramProvider();
    error NotCurator();
    error NotApplicationOwner();

    error Stage_NotSubmittedInProgram();
    error Stage_NotAcceptedInProgram();
    error Stage_NotLaunchedYet();
    error Stage_NotCompletedYet();
    
    error InvalidOwnerShare();
    error InvalidProgramRewards_LR();
    error InvalidProgramRewards_OR();
    error InvalidProgramRewards_CR();
    error InvalidProgramRewards_CA();

    error InsufficientVbioBalance();
    error InsufficientBioBalance();
    error OverdrawnVbio();
    
    error MustClaimOnceLaunched();
    
}