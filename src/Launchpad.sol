import { BaseLaunchpad } from "./BaseLaunchpad.sol";

/*  TODO add NFT to launchpad. import solady */
contract BIOLaunchpad is BaseLaunchpad  {

    /**
        NFT management
    */
    function contentURI(uint256 nftID) public returns(string) {
        // https://github.com/open-dollar/od-contracts/blob/5ca9dfed28a92c0bb452dfba0c2a62485b2d82ff/src/contracts/proxies/NFTRenderer.sol#L109-L225
    }
    
    function ownerOf(uint256 nftID) public view returns(address) {
        return curations[nftID].currentOwner;
    }

    function transfer(uint256 nftID, address to) public returns(bool) {
        // if(authorized(msg.sender , curations[nftID].currentOwner))
        // TODO issues with transfering vbio NFTs? Can claim BIO and transfer to NFT owner like we can with raw BIO. Depends if token represents stake + rewards (BIO + airdrop/auction) or just rewards (BIO always back to OG)
        // prefer if just trading rewards. makes it easier to think how to price NFT
        // adds some complexity for having original person claim BIO but better than dealing with bio/vbio differences
        // actually just handle in claim() just always send BIO to og staker and rest to currentOwner
        curations[nftID].currentOwner = to;
        return true;
    }

    /**
        Application & Curation
    */
    function submit(address program, uint8 ownerAmount, bytes32 ipfsHash) public returns(bool) {
        // TODO do we want to declare ownerAmount? Could that just be done at launch? 
        if(ownerAmount + programs[program].totalRewardsReserved > 100) revert InvalidOwnerShare();
        uint64 appID = uint64(program) >> uint64(msg.sender);
        apps[appID] = Application({
            status: APPLICATION_STATUS.STAGES.SUBMITTED,
            ownerAmount: ownerAmount,
            governance: address(0)
        });

        emit SubmitApp(program, msg.sender, ipfsHash);
    }

    function curate(uint64 appID, uint64 amount, bool isVbio) public returns(bool) {
        if(apps[appID].status != APPLICATION_STATUS.SUBMITTED) revert Stage_NotSubmittedInProgram();

        if(isVbio) {
            if(vbioLocked[msg.sender] + amount > VBIO.balance(msg.sender))  revert InsufficientVbioBalance();
        } else { // is BIO
            if(BIO.balanceOf(msg.sender) < amount) revert InsufficientBioBalance();
            // check that they dont 1. stake with vbio 2. claim vbio 3. stake with bio
            if(vbioLocked[msg.sender] >= VBIO.balance(msg.sender)) revert OverdrawnVbio(); 
        }

        uint256 curatorID = appID >> uint64(msg.sender);
        curations[curatorID] = Stake({
            currentOwner: msg.sender,
            amount: amount,
            isVbio: isVbio
        });
        apps[appID].totalStaked += amount;

        if(isVbio) {
            vbioLocked[msg.sender] += amount;
        } else {
            BIO.transferFrom(msg.sender, address(this), amount);
        }
    }

    function unstake(uint256 curatorID, bool isVbio) public returns(bool) {
        uint64 appID = uint64(curatorID >> 32);
        if(apps[appID].status == APPLICATION_STATUS.LAUNCHED) revert MustClaimOnceLaunched();
        if(msg.sender != curations[curatorID].currentOwner) revert NotCurator();

        // remove from total count for rewards. claim() doesnt remove from total because need to consistently calculate % of total.
        apps[appID].totalStaked -= curations[curatorID].amount;
        address OG = _removeCuration(curatorID, curations[curatorID]);

        return true;
    }

    function claim(uint256 curatorID) public returns(bool) {
        uint64 appID = uint64(curatorID >> 32);

        if(apps[appID].status != APPLICATION_STATUS.LAUNCHED) revert Stage_NotLaunchedYet();
        Curation memory c = curations[curatorID];
        if(msg.sender != c.currentOwner) revert NotCurator();
        uint256 stakedAmount = c.amount;
        uint256 rewardAmount = (apps[appID].rewards.totalCuratorRewards * stakedAmount) / apps[appID].totalStaked;
        
        address OG = _removeCuration(curatorID, c);
        
        // curator always gets curation rewards, not current stake holder.
        BIO.mint(OG, curatorBIOReward);
        // only bioDAO tokens go to claimer
        ERC20(apps[appID].token).transfer(c.currentOwner, rewardAmount);
        
        return true;
    }

    function _removeCuration(uint256 cID, Curation memory c) internal returns(address) {
        address OG = address(cID << 20);
        
        // return original BIO stake to curator that deposited them
        if(c.isVbio) {
            vbioLocked[OG] -= c.amount;
        } else {
            BIO.transfer(OG, c.amount);
        }
        
        delete curations[cID];

        return OG;
    }

    function _assertAppOwner(uint64 appID) internal view returns(bool) {
        if(apps[appID].governance != msg.sender) revert NotApplicationOwner();
        return true;
    }

    function launch(uint64 appID, LaunchMetadata calldata meta) public returns(address) {
        if(apps[appID].status != APPLICATION_STATUS.COMPLETED) revert Stage_NotCompletedYet();
        _assertAppOwner();
        ERC20 xdaoToken = new ERC20(meta.name, meta.symbol, meta.maxSupply);
        
        address provider = appID >> 8;
        ProgramRewards memory rates = program[provider].rewards(apps[appID].rewardProgramID);

        AppRewards memory r  = AppRewards({
            totalLiquidityReserves: (meta.maxSupply * rates.liquidityReserves) / BPS_COEFFICIENT,
            totalOperatorRewards: (meta.maxSupply * rates.operatorReward) / BPS_COEFFICIENT,
            totalCuratorRewards: (meta.maxSupply * rates.curatorReward) / BPS_COEFFICIENT,
            totalCuratorAuction: (meta.maxSupply * rates.curatorAuction) / BPS_COEFFICIENT
        });

        xdaoToken.mint(apps[appID].governance, meta.initialSupply);
        xdaoToken.mint(provider, totalOperatorRewards);
        BIO.mint(provider, operatorBIOReward);

        apps[appID].reward = r;
        apps[appID].appToken = xdaoToken;
        apps[appID].status = APPLICATION_STATUS.LAUNCHED;

        return bioDAOToken;
    }

    /**
        Program Provider
    */
    function _assertProgramProvider(uint64 appID) internal view returns(bool) {
        if(apps[appID].program != msg.sender) revert NotProgramProvider();
        return true;
    }

    function reject(uint64 appID) public returns(bool) {
        _assertProgramProvider(appID);
        if(apps[appID].status == APPLICATION_STATUS.SUBMITTED)
            apps[appID].status = APPLICATION_STATUS.REJECTED; // never enter program.
        else apps[appID].status = APPLICATION_STATUS.REMOVED; // forcibly removed from program after being accepted
        return true;
    }

    function accept(uint64 appID) public returns(bool) {
        _assertProgramProvider(appID);
        if(apps[appID].status != APPLICATION_STATUS.SUBMITTED) revert Stage_NotSubmittedInProgram();
        apps[appID].status = APPLICATION_STATUS.ACCEPTED;
        return true;
    }

    /**
    * @notice - The application that program provider wants to mark as completing the program and unlock Launchpad features
    * @param appID - The application that program provider wants to mark as complete
    * @param governance - multisig created by bioDAO during program to use for ongoing Launchpad operations e.g. launch()
    * @return - bool if app marked as complete or not
     */
    function graduate(uint64 appID, address governance) public returns(bool) {
        _assertProgramProvider(appID);
        if(apps[appID].status != APPLICATION_STATUS.ACCEPTED) revert Stage_NotAcceptedInProgram();
        apps[appID].status = APPLICATION_STATUS.COMPLETED;
        apps[appID].governance = governance;
        return true;
    }

    function setProgramRewards(ProgramRewards memory newRewards) public returns(bool) {
        if(programs[msg.sender].stakingToken == address(0)) revert NotProgramProvider();
        _setProgramRewards(msg.sender, newRewards);
    }

    function _setProgramRewards(address provider, ProgramRewards memory newRewards) internal returns(bool) {
        // MAX checks implicitly check that sum(newRewards) < 100% as well
        if(newRewards.liquidityReserves > MAX_LIQUIDITY_RESERVES_BPS) revert InvalidProgramRewards_LR();
        if(newRewards.operatorReward > MAX_OPERATOR_REWARD_BPS) revert InvalidProgramRewards_OR();
        if(newRewards.curatorReward > MAX_CURATOR_REWARDS_RESERVE_BPS) revert InvalidProgramRewards_CR();
        if(newRewards.curatorAuction > MAX_CURATOR_AUCTION_RESERVE_BPS) revert InvalidProgramRewards_CA();
        
        pRewards[provider][programs[provider].nextRewardId] = newRewards;
        programs[provider].totalRewardsReserved = newRewards.liquidityReserves + newRewards.operatorReward + newRewards.curatorReward + newRewards.curatorAuction;

        ++programs[provider].nextRewardId;
        emit UpdateProgram(provider, newRewards);
    }
    


    /**
        BIO Network Management Functions
    */

    function _assertGovernor() internal view returns(bool) {
        if(msg.sender != governance) revert NotBIOGovernor();
        return true;
    }

    function setProvider(address provider, bool allowed) public returns(bool) {
        _assertGovernor();
        if(allowed) {
            programs[provider].stakingToken = BIO;
            programs[provider].pRewards = ProgramRewards({
                liquidityReserves: 420,
                operatorRewards: 100,
                curatorRewards: 50,
                curatorAuction: 200
            });

        }
        return true;
    }

    function setLaunchCodes(address executor, string memory funcSignature) public returns(bool) {
        _assertGovernor();
        launchCodes[executor] = funcSignature;
        return true;
    }

    function setBioReactor(address reactor) public returns(bool) {
        _assertGovernor();
        bioReactor = reactor;
        return true;
    }

    function setCurationRewardRate(uint96 bioPerLaunch) public returns(bool) {
        _assertGovernor();
        operatorBIOReward = bioPerLaunch;
        return true;
    }

    function setProviderRewardRate(uint96 bioPerLaunch) public returns(bool) {
        _assertGovernor();
        curatorBIOReward = bioPerLaunch;
        return true;
    }


}