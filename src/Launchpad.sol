pragma solidity ^0.8.4;

// TODO import custom template ERC20 for all bioDAO tokens
import { ERC20 } from "solady/tokens/ERC20.sol";

import { BaseLaunchpad } from "./BaseLaunchpad.sol";
import { ILaunchCode } from "../ILaunchCode.sol";

contract BIOLaunchpad is BaseLaunchpad {
    constructor(address bioBorg) {


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
        Application memory a = apps[appID];
        _assertAppOwner(a.governance);
        _assertAppStatus(a.status, APPLICATION_STATUS.COMPLETED);

        a.status = APPLICATION_STATUS.LAUNCHED;

        // TODO allow transfers on ERC20 if we set off by default in template
        ERC20(meta.token).mint(meta.launchCode, meta.amount); // TODO include in launch template and delegate call launch()?

        return _startAuction(a.governance, meta);
    }

    function startAuction(uint64 appID, AuctionMetadata calldata meta) public returns(address) {
        Application memory a = apps[appID];
        _assertAppOwner(a.governance);
        _assertAppStatus(a.status, APPLICATION_STATUS.LAUNCHED);
        // TODO assert auction requirements e.g. startTime in future, token = app.token, amount != 0- 

        _startAuction(a.governance, meta);
    }

    function _startAuction(address manager, AuctionMetadata calldata meta) internal returns(address) {
        // TODO move all logic to launchCode.launch(). Update LaunchMetadata and create new AuctionMetadata

        // TODO clean up, parametrize. Include in accept(), launch(), auction() and 
        ERC20(meta.token).transferFrom(msg.sender, meta.launchCode); // TODO include in launch template and delegate call launch()?
        
        try(ILaunchCode(meta.launchCode).launch(manager, meta.amount, meta.startTime, meta.endTime, meta.customLaunchData)) returns (address auction) {
            // TODO. auction started. return address?
            emit Auction(meta.token, meta.amount, meta.startTime, meta.endTime);
            return auction;
        } catch {
            // TODO
            revert TakeoffFailed();
        }
    }

    
    function submit(address program, bytes32 ipfsHash) public returns(bool) {
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

    function curate(uint64 appID, uint64 amount, bool isVbio) public returns(bool) {
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.SUBMITTED);

        // TODO remove BIO. only vBIO
        if(isVbio) {
            if(vbioLocked[msg.sender] + amount > VBIO.balance(msg.sender))  revert InsufficientVbioBalance();
        } else { // is BIO
            if(BIO.balanceOf(msg.sender) < amount) revert InsufficientBioBalance();
            // check that they dont 1. stake with vbio 2. claim vbio 3. stake with bio
            if(vbioLocked[msg.sender] >= VBIO.balance(msg.sender)) revert OverdrawnVbio(); 
        }

        uint256 curationID  = _encodeID(appID, msg.sender);
        curations[curationID] = Curation({
            owner: msg.sender,
            amount: amount,
            isVbio: isVbio
        });
        apps[appID].totalStaked += amount;
        _mint(msg.sender, curationID);
        
        // TODO remove BIO. only vBIO
        if(isVbio) {
            vbioLocked[msg.sender] += amount;
        } else {
            BIO.transferFrom(msg.sender, address(this), amount);
        }

        emit Curate(appID, msg.sender, isVbio, amount, curationID);
    }

    function uncurate(uint256 curationID, bool isVbio) public returns(bool) {
        (uint96 appID, address curator) = _decodeID(curationID);

        // can unstake until rewards are claimable, then must claim to prevent locked tokens
        if(apps[appID].status == APPLICATION_STATUS.LAUNCHED) revert MustClaimOnceLaunched();
        if(msg.sender != curations[curationID].owner) revert NotCurator();

        // remove from total count for rewards. Not in _removeCuration bc claim() needs to keep total consistently calculate curator rewards %.
        apps[appID].totalStaked -= curations[curationID].amount;

        _removeCuration(curationID, curations[curationID]);
        
        emit Uncurate(curationID, msg.sender);

        return true;
    }

    function claim(uint256 curationID) public returns(bool) {
        (uint96 appID, address curator) = _decodeID(curationID);
        _assertAppStatus(apps[appID].status, APPLICATION_STATUS.LAUNCHED);
        
        Curation memory c = curations[curationID];
        if(msg.sender != c.owner) revert NotCurator();
        if(c.amount == 0) revert RewardsAlreadyClaimed();

        uint256 rewardAmount = (apps[appID].rewards.totalCuratorRewards * c.amount) / apps[appID].totalStaked;
        
        // only bioDAO tokens go to claimer
        ERC20(apps[appID].token).transfer(c.owner, rewardAmount);
        _removeCuration(curationID, c);
        // curator always gets curation rewards, not current stake holder.
        // BIO.mint(curator, curatorBIOReward); // No curation specific reward. Only private/public auction benefits

        emit Claim(curationID, msg.sender, rewardAmount, curatorBIOReward);
    
        return true;
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

    function _removeCuration(uint256 cID, Curation memory c) internal {
        (, address curator) = _decodeID(cID);
        
        // return original BIO stake to curator that deposited them
        // TODO remove BIO. only vBIO.
        if(c.isVbio) {
            vbioLocked[curator] -= c.amount;
        } else {
            BIO.transfer(curator, c.amount);
        }

        delete curations[cID];

        emit Transfer(msg.sender, address(0), cID);
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

        return _deployNewToken(appID, meta);
    }

    function _deployNewToken(uint64 appID, BorgMetadata calldata meta) private returns(address) {
        Application memory a = apps[appID];
        // TODO better token template. will be base token for all DAOs in our ecosystem
        // mintable by reactor+governance, L3s, NON-Transferrable until PUBLIC Auction, distribute 6.9% to reactor every time minted
        ERC20 xdaoToken = new ERC20(meta.name, meta.symbol, meta.maxSupply);
        
        ProgramRewards memory rates = programs[a.program].rewards[a.rewardProgramID];

        AppRewards memory r  = AppRewards({
            totalLiquidityReserves: (meta.maxSupply * rates.liquidityReserves) / BPS_COEFFICIENT,
            // totalOperatorRewards: (meta.maxSupply * rates.operatorReward) / BPS_COEFFICIENT, // pretty sure can remove from struct. Dont need besides now and stored in events for later
            // totalCuratorRewards: (meta.maxSupply * rates.curatorReward) / BPS_COEFFICIENT,
            totalCuratorAuction: (meta.maxSupply * rates.curatorAuction) / BPS_COEFFICIENT
        });

        // xdaoToken.mint(a.governance, meta.initialSupply);
        // xdaoToken.mint(operator, r.totalOperatorRewards); // TODO remove or just set to 0 initially
        BIO.mint(a.program, operatorBIOReward);

        a.reward = r;
        a.token = xdaoToken;
        a.status = APPLICATION_STATUS.ACCEPTED; // technically belongs in accept() before _deployToken but gas efficient here
        apps[appID] = a;

        return address(xdaoToken);
    }


    function setProgramRewards(ProgramRewards memory newRewards) public returns(bool) {
        if(programs[msg.sender].stakingToken == address(0)) revert NotProgramOperator();
        _setProgramRewards(msg.sender, newRewards);
    }

    function _setProgramRewards(address operator, ProgramRewards memory newRewards) internal returns(bool) {
        // MAX checks implicitly check that sum(newRewards) < 100% as well
        if(newRewards.liquidityReserves > MAX_LIQUIDITY_RESERVES_BPS) revert InvalidProgramRewards_LR();
        if(newRewards.operatorReward > MAX_OPERATOR_REWARD_BPS) revert InvalidProgramRewards_OR();
        if(newRewards.curatorReward > MAX_CURATOR_REWARDS_RESERVE_BPS) revert InvalidProgramRewards_CR();
        if(newRewards.curatorAuction > MAX_CURATOR_AUCTION_RESERVE_BPS) revert InvalidProgramRewards_CA();
        
        newRewards.totalRewardsReserved = newRewards.liquidityReserves + newRewards.operatorReward + newRewards.curatorReward + newRewards.curatorAuction;
        programs[operator].rewards[programs[operator].nextRewardId] = newRewards;

        programs[operator].nextRewardId++;

        emit UpdateProgramRewards(operator, newRewards);
    }
    

    /**
        BIO Network Management Functions
    */
    function _assertGovernor() internal view returns(bool) {
        if(msg.sender != governance) revert NotBIOGovernor();
        return true;
    }

    function setProgram(address operator, bool allowed) public returns(bool) {
        _assertGovernor();
        if(allowed) {
            programs[operator].stakingToken = BIO;
            programs[operator].rewards[0] = ProgramRewards({
                liquidityReserves: 420,
                operatorRewards: 100,
                curatorRewards: 50,
                curatorAuction: 200
            });
        }

        emit SetProgram(operator, allowed);
        return true;
    }

    function setLaunchCodes(address executor, string memory funcSignature) public returns(bool) {
        _assertGovernor();
        launchCodes[executor] = funcSignature;
        emit setLaunchCodes(executor);
        return true;
    }

    function setBioReactor(address reactor) public returns(bool) {
        _assertGovernor();
        bioReactor = reactor;
        emit SetReactor(reactor);
        return true;
    }

    function setCurationRewardRate(uint96 bioPerLaunch) public returns(bool) {
        _assertGovernor();
        operatorBIOReward = bioPerLaunch;
        return true;
    }

    function setOperatorRewardRate(uint96 bioPerLaunch) public returns(bool) {
        _assertGovernor();
        curatorBIOReward = bioPerLaunch;
        return true;
    }


    /**
        NFT shit
    */

    function name(uint256 curationID) public pure returns(string) {
        return "BIO Curated Launchpad";
    }

    function symbol(uint256 curationID) public pure returns(string) {
        return "bioCURE";
    }

    function contentURI(uint256 curationID) public returns(string) {
        // https://github.com/open-dollar/od-contracts/blob/5ca9dfed28a92c0bb452dfba0c2a62485b2d82ff/src/contracts/proxies/NFTRenderer.sol#L109-L225
    }
    
        /// @notice Find the owner of an NFT
    /// @dev NFTs assigned to zero address are considered invalid, and queries
    ///  about them do throw.
    /// @param curationID The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 curationID) public view returns(address) {
        return curations[curationID].owner;
    }

    function balanceOf(address owner) public view returns(uint256) {
        return balances[owner];
    }

    function _mint(address to, uint256 curationID) internal {
        balances[msg.sender]++;
        emit Transfer(address(0), to, curationID);
    }

    function transfer(uint256 curationID, address to) public returns(bool) {
        // if(authorized(msg.sender , curations[curationID].owner))
        // TODO issues with transfering vbio NFTs? Can claim BIO and transfer to NFT owner like we can with raw BIO. Depends if token represents stake + rewards (BIO + airdrop/auction) or just rewards (BIO always back to OG)
        // prefer if just trading rewards. makes it easier to think how to price NFT
        // adds some complexity for having original person claim BIO but better than dealing with bio/vbio differences
        // actually just handle in claim() just always send BIO to og staker and rest to owner

        _transfer(msg.sender, to, curationID);
        return true;
    }

    function transferFrom(address from, address to, uint256 curationID) public returns(bool) {
        if(msg.sender != _nftIdApprovals[curationID] || !_nftOpsApprovals[from][msg.sender])
            revert NotNFTOperator();
        _transfer(from, to, curationID);
    }

    function _assertExists(uint256 curationID) internal {
        if(!curations[curationID].amount) revert TokenDoesNotExist();
    }

    function _transfer(address from, address to, uint256 curationID) internal {
        if(from != curations[curationID].owner) revert NotCurator();
        _assertExists(curationID);
        
        _nftIdApprovals[curationID] = address(0); // reset operators so new owner isnt rugged
        curations[curationID].owner = to;
        balances[from]--;
        balances[to]++;

        emit Transfer(from, to, curationID);
     }

    /// Requirements:
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - If `to` refers to a smart contract, it must implement
    ///   {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
    function _safeTransfer(address by, address from, address to, uint256 id, bytes memory data)
        internal
        virtual
    {
        _transfer(from, to, id);
        if (_hasCode(to)) _checkOnERC721Received(from, to, id, data);
    }


    /// @notice Change or reaffirm the approved address for an NFT
    /// @dev The zero address indicates there is no approved address.
    ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
    ///  operator of the current owner.
    /// @param account The new approved NFT controller
    /// @param curationID The NFT to approve
    function approve(address account, uint256 curationID) public payable {
        _approve(msg.sender, account, curationID, true);
    }

    function setApprovalForAll(address operator, bool isApproved) public {
        _nftOpsApprovals[msg.sender][operator] = isApproved;
        emit ApprovalForAll(msg.sender, operator, isApproved);
    }

    function isApprovedForAll(address owner, bool operator) public {
        return _nftOpsApprovals[owner][operator];
    }

    function getApproved(uint256 curationID) public {
        _assertExists(curationID);
        return _nftIdApprovals[curationID];
    }

    function _assertExists(uint256 curationID) internal {
        if(!curations[curationID].owner) revert TokenDoesNotExist();
    }

    function _approve(address approver, address delegated, uint256 id) internal {
        if(approver != curations[id].owner) revert NotCurator();
        _nftIdApprovals[id] = delegated;
        emit Approval(approver, delegated, id);
    }

    /// @notice Count all NFTs assigned to an owner
    /// @dev NFTs assigned to the zero address are considered invalid, and this
    ///  function throws for queries about the zero address.
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) external view returns (uint256) {
        return balances[_owner]; // dont think this is important to us.
    }


    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT. When transfer is complete, this function
    ///  checks if `_to` is a smart contract (code size > 0). If so, it calls
    ///  `onERC721Received` on `_to` and throws if the return value is not
    ///  `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    /// @param data Additional data with no specified format, sent in call to `_to`
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes data) external payable;

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev This works identically to the other function with an extra data parameter,
    ///  except this function just sets data to "".
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;

    /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
    ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
    ///  THEY MAY BE PERMANENTLY LOST
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;


    /// @notice Enable or disable approval for a third party ("operator") to manage
    ///  all of `msg.sender`'s assets
    /// @dev Emits the ApprovalForAll event. The contract MUST allow
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved) external;

    /// @notice Get the approved address for a single NFT
    /// @dev Throws if `_tokenId` is not a valid NFT.
    /// @param _tokenId The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 _tokenId) external view returns (address);

    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);


    /// @dev Perform a call to invoke {IERC721Receiver-onERC721Received} on `to`.
    /// Reverts if the target does not support the function correctly.
    /// See: Milady
    function _checkOnERC721Received(address from, address to, uint256 id, bytes memory data)
        private
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Prepare the calldata.
            let m := mload(0x40)
            let onERC721ReceivedSelector := 0x150b7a02
            mstore(m, onERC721ReceivedSelector)
            mstore(add(m, 0x20), caller()) // The `operator`, which is always `msg.sender`.
            mstore(add(m, 0x40), shr(96, shl(96, from)))
            mstore(add(m, 0x60), id)
            mstore(add(m, 0x80), 0x80)
            let n := mload(data)
            mstore(add(m, 0xa0), n)
            if n { pop(staticcall(gas(), 4, add(data, 0x20), n, add(m, 0xc0), n)) }
            // Revert if the call reverts.
            if iszero(call(gas(), to, 0, add(m, 0x1c), add(n, 0xa4), m, 0x20)) {
                if returndatasize() {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(m, 0x00, returndatasize())
                    revert(m, returndatasize())
                }
            }
            // Load the returndata and compare it.
            if iszero(eq(mload(m), shl(224, onERC721ReceivedSelector))) {
                mstore(0x00, 0xd1a57ed6) // `TransferToNonERC721ReceiverImplementer()`.
                revert(0x1c, 0x04)
            }
        }
    }
    /// @dev Returns if `a` has bytecode of non-zero length.
    /// See: Solady
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    /// @dev Returns true if this contract implements the interface defined by `interfaceId`.
    /// See: Solady, https://eips.ethereum.org/EIPS/eip-165
    /// This function call must use less than 30000 gas.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := shr(224, interfaceId)
            // ERC165: 0x01ffc9a7, ERC721: 0x80ac58cd, ERC721Metadata: 0x5b5e139f.
            result := or(or(eq(s, 0x01ffc9a7), eq(s, 0x80ac58cd)), eq(s, 0x5b5e139f))
        }
    }

}