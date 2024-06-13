pragma solidity ^0.8.4;

// TODO import custom template ERC20 for all bioDAO tokens
import { ERC20 } from "solady/tokens/ERC20.sol";

import { BaseLaunchpad } from "./BaseLaunchpad.sol";
import { ILaunchCode } from "./interfaces/ILaunchCode.sol";

contract BIOLaunchpad is BaseLaunchpad {
    constructor(address _owner, address _bioReactor, address _curatorLaunchCode, uint96 _operatorBIOReward) {
        owner = _owner;
        bioReactor = _bioReactor;
        launchCodes[_curatorLaunchCode] = true;
        curatorLaunchCode = _curatorLaunchCode;
        operatorBIOReward = _operatorBIOReward;
    }

    /**
        bioDAO Actions - submit, launch
    */
    function _assertAppOwner(address governance) internal view {
        if(governance != msg.sender) revert NotApplicationOwner();
    }

    function _assertAppStatus(APPLICATION_STATUS currentStatus, APPLICATION_STATUS targetStatus) internal pure{
        if(currentStatus != targetStatus) revert InvalidAppStatus(currentStatus, targetStatus);
    }

    /// @notice initaite public auction of bioDAO token and 
    /// @return auction - address of new auction initiated for bioDAO launch
    function launch(uint64 appID, AuctionMetadata calldata meta) public returns(address) {
        // assert caller is applicant in _startAuction()
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.COMPLETED);
        apps[appID].status = APPLICATION_STATUS.LAUNCHED;

        return _startAuction(appID, meta);
    }

    function startAuction(uint64 appID, AuctionMetadata calldata meta) public returns(address) {
        // assert caller is applicant in _startAuction()
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.LAUNCHED);
        return _startAuction(appID, meta);
    }

    function _startAuction(uint64 appID, AuctionMetadata calldata meta) internal returns(address) {
        Application memory a = apps[appID];
        _assertAppOwner(a.governance);
        // TODO assert auction requirements e.g. startTime in future, token = app.token, amount != 0- 
        if(!launchCodes[meta.launchCode]) revert BadLaunchCode();

        // use transferFrom() not mint() to support Cohort 1 and other exogenous bioDAOs
        // TODO move more logic like token instantiation to launchCode.launch(). Update LaunchMetadata and create new AuctionMetadata
        // ERC20(meta.token).transferFrom(msg.sender, meta.launchCode); // TODO include in launch template and delegate call launch()?
        
        try(meta.launchCode.delegatecall(ILaunchCode.launch.selector, meta)) returns (bool success, bytes memory result) {
            address auction = abi.decode(result, "(address)");
            // TODO. auction started. return address?
            emit StartAuction(meta.token, meta.amount, meta.startTime, meta.endTime);
            return auction;
        } catch { 
            // TODO
            revert TakeoffFailed();
        }
    }

    
    function submit(address program, bytes32 ipfsHash) public {
        apps[nextApplicantId] = Application({
            status: APPLICATION_STATUS.STAGES.SUBMITTED,
            program: program,
            governance: address(0)
        });
        
        nextApplicantId++;
        emit SubmitApp(program, msg.sender, ipfsHash);
    }

    /*
        BIO curator actions - curate, uncurate, claim, 
    */

    function curate(uint64 appID, uint64 amount) public {
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.SUBMITTED);

        if(vbioLocked[msg.sender] + amount > VBIO.balance(msg.sender))  revert InsufficientVbioBalance();

        uint256 curationID  = _encodeID(appID, msg.sender);
        unchecked {
            // pratically wont overflow bc dispersion and uint checks on VBIO contract
            curations[curationID] = amount;
            apps[appID].totalStaked += amount;
            vbioLocked[msg.sender] += amount;
        }

        emit Curate(appID, msg.sender, amount, curationID);
    }

    function uncurate(uint256 curationID) public {
        (uint96 appID, address curator) = _decodeID(curationID);

        // can unstake until rewards are claimable, then must claim to prevent locked tokens
        if(apps[appID].status == APPLICATION_STATUS.LAUNCHED) revert MustClaimOnceLaunched();
        if(msg.sender != curator) revert NotCurator();

        // remove from total count for rewards. Not in _removeCuration bc claim() needs to keep total consistently calculate curator rewards %.
        apps[appID].totalStaked -= curations[curationID];

        _removeCuration(curationID, curations[curationID]);
        
        emit Uncurate(curationID, msg.sender);

    }

    function claim(uint256 curationID) public {
        (uint96 appID, address curator) = _decodeID(curationID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.LAUNCHED);
        
        Curation memory c = curations[curationID];
        if(msg.sender != curator) revert NotCurator();
        if(c.amount == 0) revert RewardsAlreadyClaimed();

        uint256 rewardAmount = (apps[appID].rewards.totalCuratorRewards * c.amount) / apps[appID].totalStaked;
    
        ERC20(apps[appID].token).transfer(curator, rewardAmount);
        _removeCuration(curationID, c);

        emit Claim(curationID, msg.sender, rewardAmount);
    
    }
    

    // TODO fact check bitshifts. AI generated and cant be fucked to check rn
    function _encodeID(uint96 appID, address curator) public pure returns (uint256) {
        uint96 id1 = uint96(appID);
        uint160 id2 = uint160(curator);
        // Shift the second address value to the left by 160 bits (20 bytes)
        uint64 encodedValue = uint64(id2 << 160);
        // Add the first address value to the encoded value
        uint256(encodedValue |= uint64(id1));
    }

    function _decodeID(uint256 curationID) public pure returns (uint96 appID, address curator) {
        appID = uint96(curationID);
        // Shift the value to the right by 64 bits and cast to an address
        curator = address(uint160(curationID >> 96));
    }

    function _removeCuration(uint256 cID) internal {
        (, address curator) = _decodeID(cID);

        unchecked {
            vbioLocked[curator] -= curations[cID];
        }

        delete curations[cID]; // fuck off
    }

    /**
        Program Operator - reject, accept, graduate, setProgramRewards
    */
    function _assertProgramOperator(uint64 appID) internal view {
        if(apps[appID].program != msg.sender) revert NotProgramOperator();
    }

        /**
    * @notice - The application that program operator wants to mark as completing the program and unlock Launchpad features
    * @param appID - The application that program operator wants to mark as complete
    * @param governance - multisig created by bioDAO during program to use for ongoing Launchpad operations e.g. launch()
    * @return - bool if app marked as complete or not
     */
    function graduate(uint64 appID, address governance) public {
        _assertProgramOperator(appID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.ACCEPTED);

        apps[appID].status = APPLICATION_STATUS.COMPLETED;
        apps[appID].governance = governance;
    }

    function reject(uint64 appID) public {
        _assertProgramOperator(appID);
        if(apps[appID].status == APPLICATION_STATUS.LAUNCHED) revert MustClaimOnceLaunched();
        if(apps[appID].status == APPLICATION_STATUS.SUBMITTED)
            apps[appID].status = APPLICATION_STATUS.REJECTED; // never enter program.
        else apps[appID].status = APPLICATION_STATUS.REMOVED; // forcibly removed from program after being accepted
    }

    function accept(uint64 appID, BorgMetadata calldata meta) public returns(address) {
        _assertProgramOperator(appID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.SUBMITTED);

        (address xdaoToken, uint256 curatorRewards) = _deployNewToken(appID, meta);
            
        _startAuction(appID, AuctionMetadata({
            launchCodes: curatorLaunchCode,
            token: xdaoToken,
            manager: apps[appID].owner, // TODO operator?
            amount: curatorRewards,
            startTime: unchecked { block.timestamp + 1 days },
            endTime: unchecked { block.timestamp + 8 days } // TODO sanity check
            // customLaunchData: null
        }));
    }

    function _deployNewToken(uint64 appID, BorgMetadata calldata meta) private returns(address, uint256) {
        Application memory a = apps[appID];
        // TODO better token template. will be base token for all DAOs in our ecosystem
        // mintable by reactor+governance, L3s, NON-Transferrable until PUBLIC Auction, distribute 6.9% to reactor every time minted
        ERC20 xdaoToken = new ERC20(meta.name, meta.symbol, meta.maxSupply);

        // TODO rewardID at time of submit() or accept()??
        ProgramRewards memory rates = programs[a.program].rewards[a.rewardProgramID];

        AppRewards memory r = AppRewards({
            totalLiquidityReserves: (meta.maxSupply * rates.liquidityReserves) / BPS_COEFFICIENT,
            totalCuratorAuction: (meta.maxSupply * rates.curatorAuction) / BPS_COEFFICIENT
        });

        // TODO mint to vBIO and then create vest schedule
        BIO.mint(a.program, operatorBIOReward);

        a.reward = r;
        a.token = xdaoToken;
        a.status = APPLICATION_STATUS.ACCEPTED; // technically belongs in accept() before _deployToken but gas efficient here
        apps[appID] = a;

        return (address(xdaoToken), r.totalCuratorAuction);
    }


    function setProgramRewards(ProgramRewards memory newRewards) public {
        if(programs[msg.sender].stakingToken == address(0)) revert NotProgramOperator();
        _setProgramRewards(msg.sender, newRewards);
    }

    function _setProgramRewards(address operator, ProgramRewards memory newRewards) internal {
        // MAX checks implicitly check that sum(newRewards) < 100% as well
        if(newRewards.liquidityReserves > MAX_LIQUIDITY_RESERVES_BPS) revert InvalidProgramRewards_LR();
        if(newRewards.curatorAuction > MAX_CURATOR_AUCTION_RESERVE_BPS) revert InvalidProgramRewards_CA();
        
        newRewards.totalRewardsBps = newRewards.liquidityReserves + newRewards.curatorAuction;
        Program memory p = programs[operator];

        // emit early so dont need to save old rewardId to new var
        emit SetProgramRewards(operator, p.nextRewardId, newRewards);

        p.rewards[p.nextRewardId] = newRewards;
        p.nextRewardId++;
        programs[operator] = p;
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
            programs[operator].stakingToken = BIO;
            programs[operator].rewards[0] = ProgramRewards({
                liquidityReserves: 420,
                curatorAuction: 500
            });
        }

        emit SetProgram(operator, allowed);
    }

    function setLaunchCodes(address executor, bool isAllowed) public {
        _assertOwner();
        launchCodes[executor] = isAllowed;
        emit setLaunchCodes(executor, isAllowed);
    }

    function setBioReactor(address reactor) public {
        _assertOwner();
        bioReactor = reactor;
        emit SetReactor(reactor);
    }

    function setOperatorRewardRate(uint96 bioPerLaunch) public {
        _assertOwner();
        operatorBIOReward = bioPerLaunch;
    }
}