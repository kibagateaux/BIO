pragma solidity ^0.8.4;

// TODO import custom template XDAOToken for all bioDAO tokens
import { XDAOToken } from ".//XDAOToken.sol";

import { BaseLaunchpad } from "./BaseLaunchpad.sol";
import { ILaunchCode } from "./interfaces/ILaunchCode.sol";

contract Launchpad is BaseLaunchpad {
    constructor(address _owner, address _bioBank, address _curatorLaunchCode, uint96 _operatorBIOReward, address bio, address vbio) {
        owner = _owner;
        bioBank = _bioBank;
        launchCodes[_curatorLaunchCode] = true;
        curatorLaunchCode = _curatorLaunchCode;
        operatorBIOReward = _operatorBIOReward;
        if(bio != address(0)) BIO = XDAOToken(bio);
        if(vbio != address(0)) VBIO = XDAOToken(vbio);
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
    /// @dev TODO add reentrancy
    function launch(uint96 appID, AuctionMetadata memory meta) public returns(address) {
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.COMPLETED);
        _assertAppOwner(apps[appID].governance);
        
        apps[appID].status = APPLICATION_STATUS.LAUNCHED;

        // TODO mint to vBIO and then create vest schedule
        BIO.mint(a.program, operatorBIOReward);
        emit SetApplicantStatus(appID, APPLICATION_STATUS.COMPLETED, APPLICATION_STATUS.LAUNCHED);

        return _startAuction(appID, false, meta);
    }

    /// @dev TODO add reentrancy
    function startAuction(uint96 appID, AuctionMetadata memory meta) public returns(address) {
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.LAUNCHED);
        _assertAppOwner(apps[appID].governance);
        return _startAuction(appID, false, meta);
    }

    function _startAuction(uint96 appID, bool isReserveAuction, AuctionMetadata memory meta) internal returns(address) {
        Application memory a = apps[appID];
        // TODO assert auction requirements e.g. startTime in future, token = app.token, amount != 0- 
        if(!launchCodes[meta.launchCode]) revert BadLaunchCode();
        // offload meta parameter checking to launchcodes
        if(isReserveAuction) {
            XDAOToken(meta.giveToken).transfer(meta.launchCode, meta.totalGive); // TODO include in launch template and delegate call launch()?
        } else {
            XDAOToken(meta.giveToken).transferFrom(msg.sender, meta.launchCode, meta.totalGive); // TODO include in launch template and delegate call launch()?
        }
        
        // TODO Get TPA style working
        (bool success, bytes memory result) = meta.launchCode.call(abi.encodeWithSignature("launch()"));
        if(success) {
            address auction = abi.decode(result, (address));
            // TODO. auction started. return address?
            emit StartAuction(appID, auction, meta.totalGive, meta.startTime, meta.endTime);
            return auction;
        } else {
            revert TakeoffFailed();
        }
    }

    
    function submit(address program, bytes32 ipfsHash) public returns(uint96 id){
        id = nextApplicantId;
        apps[id] = Application({
            status: APPLICATION_STATUS.SUBMITTED,
            program: program,
            //
            rewardProgramID: 0,
            totalStaked: 0,
            governance: address(0),
            token: address(0)
        });
        
        nextApplicantId++;

        emit SubmitApp(program, id, ipfsHash);
    }

    /*
        BIO curator actions - curate, uncurate, claim, 
    */
    function curate(uint96 appID, uint96 amount) public returns(uint256 curationID) {
        if(amount == 0) revert MustStakeOver0BIO();
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.SUBMITTED);
        if(vbioLocked[msg.sender] + amount > VBIO.balanceOf(msg.sender))  revert InsufficientVbioBalance();

        curationID = _encodeID(appID, msg.sender);
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

        // cant unstake once ACCEPTED and first rewards distributed, must wait till LAUNCHED and claim()
        if(apps[appID].status == APPLICATION_STATUS.ACCEPTED 
            ||  apps[appID].status == APPLICATION_STATUS.COMPLETED
            ||  apps[appID].status == APPLICATION_STATUS.LAUNCHED) revert MustClaimOnceLaunched();
        if(msg.sender != curator) revert NotCurator();

        // remove from total count for rewards. Not in _removeCuration bc claim() needs to keep total consistently calculate curator rewards %.
        apps[appID].totalStaked -= uint128(curations[curationID]);

        _removeCuration(curationID, curator);
        
        emit Uncurate(curationID);

    }

    function claim(uint256 curationID) public {
        (uint96 appID, address curator) = _decodeID(curationID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.LAUNCHED);
        
        uint256 c = curations[curationID];
        if(msg.sender != curator) revert NotCurator();
        if(c == 0) revert RewardsAlreadyClaimed();

        // uint256 rewardAmount = (rewards[appID].totalCuratorRewards * c) / apps[appID].totalStaked;
        uint256 rewardAmount = 0;

        // TODO give BIO emission?
        // BIO.mint(curator, curatorBIOReward * c / BPS_COEFFICIENT)
        // XDAOToken(apps[appID].token).transfer(curator, rewardAmount);
        _removeCuration(curationID, curator);

        emit Claim(curationID, rewardAmount);
    
    }
    

    // TODO fact check bitshifts. AI generated and cant be fucked to check rn
    function _encodeID(uint96 appID, address curator) public pure returns (uint256) {
        uint96 id1 = uint96(appID);
        uint160 id2 = uint160(curator);
        // Shift the second address value to the left by 160 bits (20 bytes)
        uint96 encodedValue = uint96(id2 << 160);
        // Add the first address value to the encoded value
        return uint256(id1 |= encodedValue);
    }

    function _decodeID(uint256 curationID) public pure returns (uint96 appID, address curator) {
        appID = uint96(curationID);
        // Shift the value to the right by 64 bits and cast to an address
        curator = address(uint160(curationID >> 96));
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
    * @param governance - multisig created by bioDAO during program to use for ongoing Launchpad operations e.g. launch()
     */
    function graduate(uint96 appID, address governance) public {
        _assertProgramOperator(appID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.ACCEPTED);

        apps[appID].status = APPLICATION_STATUS.COMPLETED;
        apps[appID].governance = governance;
        emit SetApplicantStatus(appID, APPLICATION_STATUS.ACCEPTED, APPLICATION_STATUS.COMPLETED);
    }

    function reject(uint96 appID) public {
        _assertProgramOperator(appID);
        if(apps[appID].status == APPLICATION_STATUS.LAUNCHED)
            revert MustClaimOnceLaunched();
        if(apps[appID].status == APPLICATION_STATUS.SUBMITTED) {
            apps[appID].status = APPLICATION_STATUS.REJECTED; // never enter program.
            emit SetApplicantStatus(appID, APPLICATION_STATUS.SUBMITTED, APPLICATION_STATUS.REJECTED);
        }

        if(apps[appID].status == APPLICATION_STATUS.ACCEPTED
            || apps[appID].status == APPLICATION_STATUS.COMPLETED
        ) {
            apps[appID].status = APPLICATION_STATUS.REMOVED; // forcibly removed from program after being accepted
            emit SetApplicantStatus(appID, apps[appID].status, APPLICATION_STATUS.REMOVED);
        }
    }

    /// @dev TODO add reentrancy
    function accept(uint96 appID, OrgMetadata calldata meta) public returns(address, address) {
        _assertProgramOperator(appID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.SUBMITTED);

        (address xdaoToken, uint256 curatorRewards) = _deployNewToken(appID, meta);
        uint32 startTime;
        uint32 endTime;
        bytes[] memory customData;
        unchecked {
            (startTime, endTime) = (uint32(block.timestamp + 1 days), uint32(block.timestamp + 8 days));
        }

        address auction = _startAuction(appID, true, AuctionMetadata({
            launchCode: curatorLaunchCode,
            giveToken: xdaoToken,
            manager: apps[appID].governance, // TODO operator?
            totalGive: uint128(curatorRewards),
            startTime: startTime,
            endTime: endTime,
            wantToken: address(0), // set to usdc LaunchCode factory
            totalWant: meta.valuation * curatorRewards / meta.totalSupply, // usdc denominated
            customLaunchData: customData
        }));

        return (xdaoToken, auction);
    }

    function _deployNewToken(uint96 appID, OrgMetadata calldata meta) private returns(address, uint256) {
        Application memory a = apps[appID];
        // TODO better token template. will be base token for all DAOs in our ecosystem
        // mintable by reactor+governance, L3s, NON-Transferrable until PUBLIC Auction, distribute 6.9% to reactor every time minted
        XDAOToken xdaoToken = new XDAOToken(meta.name, meta.symbol);

        // TODO rewardID at time of submit() or accept()??
        ProgramRewards memory rates = pRewards[a.program][a.rewardProgramID];

        AppRewards memory r = AppRewards({
            totalLiquidityReserves: uint128((meta.maxSupply * rates.liquidityReserves) / BPS_COEFFICIENT),
            totalCuratorAuction: uint128((meta.maxSupply * rates.curatorAuction) / BPS_COEFFICIENT)
        });

        rewards[appID] = r;
        a.token = address(xdaoToken);
        a.status = APPLICATION_STATUS.ACCEPTED; // technically belongs in accept() before _deployToken but gas efficient here
        apps[appID] = a;

        emit SetApplicantStatus(appID, APPLICATION_STATUS.SUBMITTED, APPLICATION_STATUS.ACCEPTED);
        emit Launch(appID, address(xdaoToken), r.totalCuratorAuction, r.totalLiquidityReserves);

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
            programs[operator].stakingToken = address(BIO);
            pRewards[operator][0] = ProgramRewards({
                totalRewardsBps: 920,
                liquidityReserves: 420,
                curatorAuction: 500
            });
        }

        emit SetProgram(operator, allowed);
    }

    /// @notice lets bio governance allow DAOs that didnt launch through this contract to use it for future token launches
    function setExoDAO(address program, address newXDAO, address token) public {
        _assertOwner();

        apps[nextApplicantId] = Application({
            status: APPLICATION_STATUS.LAUNCHED,
            program: program,
            rewardProgramID: programs[program].nextRewardId - 1,
            totalStaked: 0,
            governance: newXDAO,
            token: token
        });
        
        nextApplicantId++;
    }

    function setLaunchCodes(address executor, bool isAllowed) public {
        _assertOwner();
        launchCodes[executor] = isAllowed;
        emit SetLaunchCodes(executor, isAllowed);
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