pragma solidity ^0.8.23;

import { TokenVesting } from "@bio/vesting/TokenVesting.sol";


// import { BioToken } from "../../BioToken.sol";
import { XDAOToken } from "./XDAOToken.sol";

abstract contract BaseLaunchpad {
    enum AplicationStatus { NULL, SUBMITTED, ACCEPTED, REJECTED, COMPLETED, REMOVED, LAUNCHED }
    // slot
    bytes32 constant _VESTING_ADMIN_ROLE = bytes32(0x00); // see OZ AccessRoles.sol
    bytes32 constant _VESTING_ROLE = keccak256("VESTING_CREATOR_ROLE"); // see TokenVesting.sol
    // slot
    uint16 constant _BPS_COEFFICIENT = 10_000; // xDAO tokens reserved for BIO liquidity pairs
    uint16 constant _MAX_LIQUIDITY_RESERVES_BPS = 1_000; // 10% -  xDAO tokens reserved for BIO liquidity pairs
    uint16 constant _MAX_OPERATOR_REWARD_BPS = 8_000; // 80% - max 80% of a token can go org running a cohort. namely bioDAOs for their IPTs
    uint16 constant _MAX_CURATOR_AUCTION_RESERVE_BPS = 2_090; // 20% - xDAO tokens reserved for Curators to applicants
    XDAOToken public bio = XDAOToken(address(0xB10));
    // slot
    TokenVesting public vbio = TokenVesting(address(0xeB10));
    XDAOToken public usdc = XDAOToken(address(0x05D));
    uint96 public nextApplicantId; // global applicant ID pool
    // slot
    address public owner; // BIO Network governance manager
    uint96 public operatorBIOReward; // BIO per launch() in a program. TODO should be pro-rata curator reward too?
    // slot
    address public bioBank; // BIO Network liquidity manager
    // uint96 curatorBIOReward; // BIO per 10,000 BIO staked e.g. 10 / BPS_COEFFICIENT. Positions < 10,000 wont get curation rewards
    // slot
    address public curatorLaunchCode = address(0x0); // default launch code for private curator auctions on accept()
    

    // bioDAOs. ID = uint64 to encode with curator address into uint256
    mapping(uint96 => Application) public apps; // bioDAO entry in launchpad registry
    mapping(uint96 => AppRewards) public rewards; // how much of bioDAO token go to curators and liquidity after launch
    mapping(address => mapping(uint16 => ProgramRewards)) public pRewards;
    mapping(uint96 => mapping(uint16 => address)) public auctions;
    
    // curators
    mapping(uint256 => uint256) public curations; // curator stakes to individual applicants
    mapping(address => uint256) public vbioLocked; // (how much vested BIO someone has staked already)
    // BIO gov
    mapping(address =>  Program) public programs;// programId -> rewardNonce -> reward rates across bioDAOs in program
    mapping(address =>  bool) public launchCodes;// approved templatized token sale strategies for bioDAOs to use

    // Launchpad Usage Events
    event SetApplicantStatus(uint96 indexed applicant, AplicationStatus indexed oldStatus, AplicationStatus indexed newStatus);
    event SubmitApp(address indexed program, uint96 applicantID, bytes32 ipfsHash);
    event Curate(uint96 indexed applicant, address indexed curator, uint256 amount, uint256 curationID);
    event Uncurate(uint256 indexed curationID);
    event Claim(uint256 indexed curationId, uint256 xdaoAmount);
    event Launch(uint96 indexed applicant, address token, address vestingToken, uint256 curatorAuctionReserves, uint256 liquidityReserves);
    event StartAuction(uint96 indexed applicant, uint16 auctionID, address auction, uint256 amount, uint32 startDate, uint32 endDate);
    event FailedToVest(uint96 indexed appID, address indexed vestingContract, address indexed auction);

    // Launchpad Admin Events
    event SetProgram(address indexed program, bool approval);
    event SetReactor(address indexed program);
    event SetLaunchCodes(address indexed executor, bool isAllowed, bool isCuratorCode);
    event SetProgramRewards(address indexed program, uint16 rewardId, ProgramRewards rewards);

    struct ProgramRewards {
        uint16 liquidityReserves;//  (e.g. 10% = 1000)
        uint16 curatorAuction; // (e.g. 0.5% = 50) // TODO remove bc standardized?
    }

    struct Program {
        address stakingToken;
        uint16 nextRewardId;
    }

    struct Application {
        // slot
        AplicationStatus status;
        uint16 rewardProgramID; // rewards at time of accepted (not applied)
        uint16 nextLaunchID;
        address program;
        // slot
        address manager;
        // slot
        uint256 totalStaked;
        // slot
        address token;
        // slot
        address vestingContract;
    }

    struct AppRewards {
        uint128 totalLiquidityReserves; // (in xDAO token, w/ xDAO token decimals)
        uint128 totalCuratorAuction; // (in xDAO token, w/xDAO token decimals)
    }

    struct OrgMetadata {
        uint256 valuation; // 8 decimal usdc valuation
        uint256 maxSupply; // total max supply of new xDAO token
        string name; // token name
        string symbol; // token symbol
    }


    error NotOwner();
    error NotProgramOperator();
    error NotBioBank();
    error NotCurator();
    error NotApplicationOwner();

    error InvalidAppStatus(AplicationStatus current, AplicationStatus target);
    error TakeoffFailed();

    error LaunchesPaused();
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