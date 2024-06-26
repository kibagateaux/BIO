pragma solidity ^0.8.23;

// TODO import custom template XDAOToken for all bioDAO tokens


// import { BioToken } from "../../BioToken.sol";
import { XDAOToken } from "./XDAOToken.sol";
import { BaseLaunchpad } from "./BaseLaunchpad.sol";
import { Utils } from "./Utils.sol";

import { TokenVesting } from "@bio/vesting/TokenVesting.sol";
import { ILaunchFactory, ILaunchCode } from "./interfaces/ILaunchCode.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

contract Launchpad is BaseLaunchpad {
    constructor(address _owner, address _bioBank, uint96 _operatorBIOReward, address _bio, address _vbio, address _usdc) {
        owner = _owner;
        bioBank = _bioBank;
        usdc = XDAOToken(_usdc);
        operatorBIOReward = _operatorBIOReward;
        if(_bio != address(0)) bio = XDAOToken(_bio);
        if(_vbio != address(0)) vbio = TokenVesting(_vbio);
    }

    /**
        bioDAO Actions - submit, launch
    */
    function _assertAppManager(address manager) internal view {
        if(manager != msg.sender) revert NotApplicationOwner();
    }

    function _assertAppStatus(AplicationStatus currentStatus, AplicationStatus targetStatus) internal pure{
        if(currentStatus != targetStatus) revert InvalidAppStatus(currentStatus, targetStatus);
    }

    /// @notice initaite public auction of bioDAO token and 
    /// @return auction - address of new auction initiated for bioDAO launch
    /// @dev TODO add reentrancy
    function launch(uint96 appID, Utils.AuctionMetadata memory meta) public returns(address) {
        _assertAppStatus(apps[appID].status, AplicationStatus.COMPLETED);
        _assertAppManager(apps[appID].manager);
        
        apps[appID].status = AplicationStatus.LAUNCHED;

        // TODO mint to vBIO and then create vest schedule
        bio.mint(apps[appID].program, operatorBIOReward);
        emit SetApplicantStatus(appID, AplicationStatus.COMPLETED, AplicationStatus.LAUNCHED);

        return _startAuction(appID, false, meta);
    }

    /// @dev TODO add reentrancy
    function startAuction(uint96 appID, Utils.AuctionMetadata memory meta) public returns(address) {
        _assertAppStatus(apps[appID].status, AplicationStatus.LAUNCHED);
        _assertAppManager(apps[appID].manager);
        return _startAuction(appID, false, meta);
    }

    function _startAuction(uint96 appID, bool isReserveAuction, Utils.AuctionMetadata memory meta) internal returns(address) {
        Application memory a = apps[appID];
        // TODO assert auction requirements e.g. startTime in future, token = app.token, amount != 0- 
        if(!launchCodes[meta.launchCode]) revert BadLaunchCode();
        // offload meta parameter checking to launchcodes
        if(isReserveAuction) {
            XDAOToken(meta.giveToken).mint(meta.launchCode, meta.totalGive); // TODO include in launch template and delegate call launch()?
        } else {
            XDAOToken(meta.giveToken).transferFrom(msg.sender, meta.launchCode, meta.totalGive); // TODO include in launch template and delegate call launch()?
        }
        
        (bool success, bytes memory result) = meta.launchCode.call(
            abi.encodeWithSelector(
                ILaunchFactory.launch.selector,
                meta
            )
        );

        if(success) {
            address auction = abi.decode(result, (address));
            auctions[appID][a.nextLaunchID] = auction;
            emit StartAuction(appID, a.nextLaunchID, auction, meta.totalGive, meta.startTime, meta.endTime);

            a.nextLaunchID++;
            apps[appID] = a;
            
            // give new auction ability to create vesting schedules.
            // TokenVesting vesting = TokenVesting(apps[appID].vestingContract.);
            (bool success2, bytes memory result2) = apps[appID].vestingContract.call(
                abi.encodeWithSignature(
                    "grantRole(bytes32,address)",
                    _VESTING_ROLE,
                    auction
                )
            );

            if (!success2) revert AuctionVestingFailed();

            return auction;
        } else {
            revert TakeoffFailed();
        }
    }

    
    function submit(address program, bytes32 ipfsHash) public returns(uint96 id){
        id = nextApplicantId;
        apps[id] = Application({
            status: AplicationStatus.SUBMITTED,
            nextLaunchID: 0,
            program: program,
            //
            rewardProgramID: 0,
            totalStaked: 0,
            manager: address(0), // todo default to bioNetwork or program?
            token: address(0),
            vestingContract: address(0)
        });
        
        nextApplicantId++;

        emit SubmitApp(program, id, ipfsHash);
    }

    function eject(uint96 appID) public {
        _assertAppManager(apps[appID].manager);
        _assertAppStatus(apps[appID].status, AplicationStatus.LAUNCHED);
        // release bioDAO infra from BIO Launchpad
        // transfer token + vesting admin roles
        // what else?
        // 
    }

    /*
        BIO curator actions - curate, uncurate, claim, 
    */
    function curate(uint96 appID, uint96 amount) public returns(uint256 curationID) {
        if(amount == 0) revert MustStakeOver0BIO();
        _assertAppStatus(apps[appID].status, AplicationStatus.SUBMITTED);
        uint256 newLockedBalance = vbioLocked[msg.sender] + amount;
        if(newLockedBalance > vbio.balanceOf(msg.sender))  revert InsufficientVbioBalance();

        curationID = _encodeID(appID, msg.sender);
        unchecked {
            // pratically wont overflow bc dispersion and uint checks on VBIO contract
            curations[curationID] = amount;
            apps[appID].totalStaked += amount;
            vbioLocked[msg.sender] = newLockedBalance;
        }

        emit Curate(appID, msg.sender, amount, curationID);
    }

    function uncurate(uint256 curationID) public {
        (uint96 appID, address curator) = _decodeID(curationID);

        // cant unstake once ACCEPTED and first rewards distributed, must wait till LAUNCHED and claim()
        if(apps[appID].status == AplicationStatus.ACCEPTED 
            ||  apps[appID].status == AplicationStatus.COMPLETED
            ||  apps[appID].status == AplicationStatus.LAUNCHED) revert MustClaimOnceLaunched();
        // if(msg.sender != curator) revert NotCurator();

        // remove from total count for rewards. Not in _removeCuration bc claim() needs to keep total consistently calculate curator rewards %.
        apps[appID].totalStaked -= uint128(curations[curationID]);

        _removeCuration(curationID, curator);
        
        emit Uncurate(curationID);
    }

    function claim(uint256 curationID) public {
        (uint96 appID, address curator) = _decodeID(curationID);
        // _assertAppStatus(apps[appID].status, AplicationStatus.LAUNCHED);
        // since auction is on accept they need to be able to claim before it actually launches()
        // maybe 2 reward stages, ACCEPTED - private auction. LAUNCHED - BIO + public auction discount?
        // _assertAppStatus(apps[appID].status, AplicationStatus.ACCEPTED);
        if(msg.sender != curator) revert NotCurator();
        if(apps[appID].status != AplicationStatus.ACCEPTED 
            &&  apps[appID].status != AplicationStatus.COMPLETED
            &&  apps[appID].status != AplicationStatus.LAUNCHED) revert MustClaimOnceLaunched();
        uint256 c = curations[curationID];
        if(c == 0) revert RewardsAlreadyClaimed();
        

        _removeCuration(curationID, curator); // wouldnt want to delete if we use later for launchcodes e.g. perpetual discounts to stakers for lifetime of bioDAO

        // TODO give BIO emission?
        // $300k to operator = ~16.9M BIO. 30% of supply staking = ~1B BIO. across 5 bioDAOs = ~8% return over duration (~1 yr)
        // uint256 bioReward = operatorBIOReward * c / apps[appID].totalStaked;
        uint256 bioReward = 0;
        // bio.mint(address(vbio), bioReward);
        // vest BIO linearly for 1 year released daily
        // vbio.createVestingSchedule(curator, block.timestamp, 0, 365 days, 60, true, bioReward);

        (bool success, bytes memory result) = auctions[appID][0].call(abi.encodeWithSelector(ILaunchCode.claim.selector, curationID, c));
        if(!success) revert LaunchCodeClaimFailed();
        
        emit Claim(curationID, bioReward);
    }
    

    // TODO fact check bitshifts. AI generated and cant be fucked to check rn
    function _encodeID(uint96 appID, address curator) public pure returns (uint256  result) {
        // appID as first 12 bytes (shift 160 bits from end)
        assembly {
            result := shl(160, appID)
            result := or(result, shl(0, curator))
        }
    }

    function _decodeID(uint256 curationID) public pure returns (uint96 appID, address curator) {
        appID = uint96(curationID >> 160);
        // Shift the value to the right by 64 bits and cast to an address
        curator = address(uint160(curationID));
    }

    function _removeCuration(uint256 cID, address curator) internal {
        unchecked {
            vbioLocked[curator] -= curations[cID];
        }

        delete curations[cID]; // fuck off
    }
    /**
        Program Operator - reject, accept, graduate, setProgramRewards
    */
    function _assertBioBank() internal view {
        if(bioBank != msg.sender) revert NotBioBank();
    }

    function pullLiquidityReserves(uint96 appID, uint256 amount) public {
        _assertBioBank();
        rewards[appID].totalLiquidityReserves -= uint128(amount);
        XDAOToken(apps[appID].token).transfer(bioBank, amount);
    }

    /**
        Program Operator - reject, accept, graduate, setProgramRewards
    */
    function _assertProgramOperator(uint96 appID) internal view {
        if(apps[appID].program != msg.sender) revert NotProgramOperator();
    }

        /**
    * @notice - The application that program operator wants to mark as completing the program and unlock Launchpad features
    * @param appID - The application that program operator wants to mark as complete
    * @param manager - multisig created by bioDAO during program to use for ongoing Launchpad operations e.g. launch()
     */
    function graduate(uint96 appID, address manager) public {
        // TODO manager needs to be set in accept() so we can send funds to them
        _assertProgramOperator(appID);
        _assertAppStatus(apps[appID].status, AplicationStatus.ACCEPTED);

        apps[appID].status = AplicationStatus.COMPLETED;
        apps[appID].manager = manager;
        emit SetApplicantStatus(appID, AplicationStatus.ACCEPTED, AplicationStatus.COMPLETED);
    }

    function reject(uint96 appID) public {
        _assertProgramOperator(appID);
        if(apps[appID].status == AplicationStatus.LAUNCHED)
            revert MustClaimOnceLaunched();
        if(apps[appID].status == AplicationStatus.SUBMITTED) {
            apps[appID].status = AplicationStatus.REJECTED; // never enter program.
            emit SetApplicantStatus(appID, AplicationStatus.SUBMITTED, AplicationStatus.REJECTED);
        }

        if(apps[appID].status == AplicationStatus.ACCEPTED
            || apps[appID].status == AplicationStatus.COMPLETED
        ) {
            apps[appID].status = AplicationStatus.REMOVED; // forcibly removed from program after being accepted
            emit SetApplicantStatus(appID, apps[appID].status, AplicationStatus.REMOVED);
        }
    }

    /// @dev TODO add reentrancy
    function accept(uint96 appID, OrgMetadata calldata meta) public returns(address, address) {
        _assertProgramOperator(appID);
        _assertAppStatus(apps[appID].status, AplicationStatus.SUBMITTED);
        if(curatorLaunchCode == address(0)) revert LaunchesPaused();

        (address xdaoToken, uint256 curatorRewards) = _deployNewToken(appID, meta);
        // 189216000
        bytes memory customData = abi.encode(apps[appID].totalStaked, apps[appID].vestingContract, 189216000); // 189216000 = 6 years in seconds

        address auction = _startAuction(appID, true, Utils.AuctionMetadata({
            launchCode: curatorLaunchCode,
            giveToken: xdaoToken,
            totalGive: uint128(curatorRewards),
            wantToken: address(usdc),
            // total usdc tokens sold to curtors. TODO check doesnt exceed uint128 limit
            totalWant: uint128((meta.valuation * 1e8 * curatorRewards) / meta.maxSupply), 
            startTime: uint32(block.timestamp + 1 days),
            endTime: uint32(block.timestamp + 8 days),
            // manager: apps[appID].manager, // TODO add xdao.governance param to accept()
            manager: owner,
            customLaunchData: customData
        }));

        return (xdaoToken, auction);
    }

    function _deployNewToken(uint96 appID, OrgMetadata calldata meta) private returns(address, uint256) {
        Application memory a = apps[appID];
        // TODO better token template. will be base token for all DAOs in our ecosystem
        // mintable by reactor+manager, L3s, NON-Transferrable until PUBLIC Auction, distribute 6.9% to reactor every time minted
        XDAOToken xdaoToken = new XDAOToken(meta.name, meta.symbol);
        TokenVesting vesting = new TokenVesting(
            address(xdaoToken),
            string.concat("v", meta.name),
            string.concat("v", meta.symbol),
            a.manager
        );

        // TODO rewardID at time of submit() or accept()??
        ProgramRewards memory rates = pRewards[a.program][a.rewardProgramID];

        AppRewards memory r = AppRewards({
            totalLiquidityReserves: uint128((meta.maxSupply * rates.liquidityReserves) / _BPS_COEFFICIENT),
            totalCuratorAuction: uint128((meta.maxSupply * rates.curatorAuction) / _BPS_COEFFICIENT)
        });

        rewards[appID] = r;
        a.token = address(xdaoToken);
        a.vestingContract = address(vesting);
        a.status = AplicationStatus.ACCEPTED; // technically belongs in accept() before _deployToken but gas efficient here
        apps[appID] = a;

        emit SetApplicantStatus(appID, AplicationStatus.SUBMITTED, AplicationStatus.ACCEPTED);
        emit Launch(appID, address(xdaoToken), address(vesting), r.totalCuratorAuction, r.totalLiquidityReserves);

        // TODO manager needs to be set in accept() so we can send funds to them
        // Or move this to separate eject() function with token ownership. I kinda like the exit rights for bioDAOs
        // vesting.beginDefaultAdminTransfer(a.manager); // give them full admin access

        return (address(xdaoToken), r.totalCuratorAuction);
    }


    function setProgramRewards(ProgramRewards memory newRewards) public {
        if(programs[msg.sender].stakingToken == address(0)) revert NotProgramOperator();
        _setProgramRewards(msg.sender, newRewards);
    }

    function _setProgramRewards(address operator, ProgramRewards memory newRewards) internal {
        // MAX checks implicitly check that sum(newRewards) < 100% as well
        if(newRewards.liquidityReserves > _MAX_LIQUIDITY_RESERVES_BPS) revert InvalidProgramRewards_LR();
        if(newRewards.curatorAuction > _MAX_CURATOR_AUCTION_RESERVE_BPS) revert InvalidProgramRewards_CA();
        
        Program storage p = programs[operator];

        // emit early so dont need to save old rewardId to new var
        emit SetProgramRewards(operator, p.nextRewardId, newRewards);

        pRewards[operator][p.nextRewardId] = newRewards;
        p.nextRewardId++;
    }
    

    /**
        BIO Network Management Functions
    */
    function _assertOwner() internal view {
        if(msg.sender != owner) revert NotOwner();
    }

    function setProgram(address operator, bool allowed) public {
        _assertOwner();
        if(allowed) {
            programs[operator].stakingToken = address(bio);
            pRewards[operator][0] = ProgramRewards({
                liquidityReserves: 420,
                curatorAuction: 200
            });
        }

        emit SetProgram(operator, allowed);
    }

    /// @notice lets bio manager allow DAOs that didnt launch through this contract to use it for future token launches
    function setExoDAO(address program, address newXDAO, address token, address vestingContract) public {
        _assertOwner();

        apps[nextApplicantId] = Application({
            status: AplicationStatus.LAUNCHED,
            program: program,
            nextLaunchID: 0,
            rewardProgramID: programs[program].nextRewardId - 1,
            totalStaked: 0,
            manager: newXDAO,
            token: token,
            vestingContract: vestingContract
        });
        
        nextApplicantId++;
    }

    function setLaunchCodes(address executor, bool isAllowed, bool isCuratorCode) public {
        _assertOwner();
        launchCodes[executor] = isAllowed;
        if(isCuratorCode && isAllowed) curatorLaunchCode = executor;
        emit SetLaunchCodes(executor, isAllowed, isCuratorCode);
    }

    function setBioReactor(address reactor) public {
        _assertOwner();
        bioBank = reactor;
        emit SetReactor(reactor);
    }

    function setOperatorRewardRate(uint96 bioPerLaunch) public {
        _assertOwner();
        operatorBIOReward = bioPerLaunch;
    }
}