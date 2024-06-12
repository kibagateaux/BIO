abstract contract BaseLaunchpad {
    enum APPLICATION_STATUS { SUBMITTED, ACCEPTED, REJECTED, COMPLETED, REMOVED, LAUNCHED }
    // slot 0
    uint16 constant BPS_COEFFICIENT = 10_000; // xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_LIQUIDITY_RESERVES_BPS = 1000; //10% -  xDAO tokens reserved for BIO liquidity pairs
    uint16 constant MAX_OPERATOR_REWARD_BPS = 8000; // 80% - max 80% of a token can go org running a cohort. namely bioDAOs for their IPTs
    uint16 constant MAX_CURATOR_REWARDS_RESERVE_BPS = 100; // 1% - xDAO tokens reserved for Curators to applicants
    uint16 constant MAX_CURATOR_AUCTION_RESERVE_BPS = 590; // 5.9% - xDAO tokens reserved for Curators to applicants
    address constant BIO = address(0xB10);
    // slot 1
    address constant VBIO = address(0xB10);
    uint96 nextApplicantId; // global applicant ID pool
    // slot 2
    address governance; // BIO Network governance manager
    uint96 operatorBIOReward; // BIO per launch() in a program
    // slot 3
    address bioReactor; // BIO Network liquidity manager
    uint96 curatorBIOReward; // BIO per launch() staked in
    // slot 4
    address acceptanceLaunch = address(0x0); // default launch code for private curator auctions on accept()

    mapping(address => uint256) vbioLocked; // (how much vested BIO someone has staked already)
    mapping(uint64 => Application) apps; // bioDAO entry in launchpad
    mapping(uint64 => AppRewards) rewards; // bioDAO entry in launchpad
    mapping(uint256 => Curation) curations; // bioDAO entry in launchpad
    mapping(address =>  Program) programs;// programId  → rewardNonce → reward rates across bioDAOs in program
    mapping(address =>  string) launchCodes;// templatize GTM playbooks for bioDAOs. launchcode => expectedFuncSignature?
    

    mapping(address =>  uint256) balances; // amount of NFTs owned
    // Mapping from token ID to approved address
    mapping (uint256 => address) _nftIdApprovals;
    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) _nftOpsApprovals;

    // Launchpad Usage Events
    event SubmitApp(address indexed program, address indexed applicant, uint256 ownerAmount);
    event Curate(uint64 indexed applicant, address indexed curator, bool indexed isVbio, uint256 amount, uint256 curationID);
    event Uncurate(uint256 indexed curationID, address indexed curator); // TODO can remove curator  if not doing NFT tokenization
    event Claim(uint256 indexed curationId,  address indexed claimer, uint256 bioAmount, uint256 xdaoAmount);
    event Launch(uint64 applicant,  address token, uint256 initSupply, uint256 liquidityReserves);
    event Auction(uint64 indexed applicant,  uint256 initSupply, uint32 startDate, uint32 endDate);
    
    // Launchpad Admin Events
    event SetProgram(address indexed program, bool approval);
    event SetReactor(address indexed program);
    event SetLaunchCodes(address indexed executor);
    event UpdateProgramRewards(address indexed program, ProgramRewards rewards);
    

    struct ProgramRewards {
        uint16 totalRewardsReserved;
        // all bps of bioDAO token to distribute to each pool.
        uint16 liquidityReserves;//  (e.g. 4% = 400)
        uint16 operatorReward; // (e.g. 2% = 200) // TODO remove
        uint16 curatorReward; // (e.g. 0.5% = 50) // TODO remove
        uint16 curatorAuction; // (e.g. 0.5% = 50) // TODO remove
    }

    struct Program {
        // address programID = provider
        uint16 nextRewardId;
        address stakingToken;
        mapping(uint16 =>  ProgramRewards) pRewards;
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
        // uint64 appID = unit64(uint32 programId, uint16 nonce)
        uint128 totalLiquidityReserves; // (in xDAO token, w/ xDAO token decimals)
        // uint128 totalOperatorRewards; // (in xDAO token, w/ xDAO token decimals)
        // uint128 totalCuratorRewards; // (in xDAO token, w/ xDAO token decimals)
        uint128 totalCuratorAuction; // (in xDAO token, w/xDAO token decimals)
    }

    struct Curation {
        // uint256 *stakeID* = unit256(uint64 appID, uint64 stake)
        address owner;
        uint96 amount;
        bool isVbio;
    }

    struct BorgMetadata {
        uint256 maxSupply; // total max supply of new xDAO token
        string name; // token name
        string symbol; // token symbol
    }

    struct AuctionMetadata {
        address launchCode;
        address token;
        uint128 amount; // initial xDAO treasury (excl BIO reserves annd rewards)
        uint32  startTime; // unix timestamp or block depending on launchCode
        uint32  endTime;
        bytes[] customLaunchData; // (for launch provider if needed for auction settings or something)
    }


    error NotBIOGovernor();
    error NotProgramOperator();
    error NotCurator();
    error NotApplicationOwner();

    error InvalidAppStatus(APPLICATION_STATUS current, APPLICATION_STATUS target);
    error TakeoffFailed();

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
    


    

    // ERC721 events

    error NotNFTOperator();
    error TokenDoesNotExist();


    /// @dev This emits when ownership of any NFT changes by any mechanism.
    ///  This event emits when NFTs are created (`from` == 0) and destroyed
    ///  (`to` == 0).
    event Transfer(address indexed _from, address indexed _to, uint256 indexed _tokenId);

    /// @dev This emits when the approved address for an NFT is changed or
    ///  reaffirmed. The zero address indicates there is no approved address.
    ///  When a Transfer event emits, this also indicates that the approved
    ///  address for that NFT (if any) is reset to none.
    event Approval(address indexed _owner, address indexed _approved, uint256 indexed _tokenId);

    /// @dev This emits when an operator is enabled or disabled for an owner.
    ///  The operator can manage all NFTs of the owner.
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

}