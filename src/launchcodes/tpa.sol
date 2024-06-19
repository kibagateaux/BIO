import { ILaunchCode } from "../interfaces/ILaunchCode.sol";

// // we set the valuation


// // specific % of xDAO token for sale (5%)
// // store amount of token per bioDAO `sales.[appID]
// // minimum $200k for sale to complete, max $1M
// // offered OTC to curators pro-rata BIO staked 
// // unclaimed xDAO tokens sent to treasury (or rolled into public auction)
// // Hve time deadline. If not complete by deadline, any BIO holder (>100,000) can purchase tokens
// // once sale complete then claimable by purchasers

contract ProRata is ILaunchCode {

    // Only function delegatecall'ed by Launchpad, rest are normal contract interactions
    function launch(address governance, uint256 tokensAuctioned, uint32 startDate, uint32 endDate) external returns(address) {
        // TODO OBJECTIVE: prorata split token amount between BIO Stakers.
        // Contract needs to claim 
        // address claimContract = new ProRata();
        // claimContract.initialize();
        // return claimContract;
    }

    function validateData(bytes[] calldata inputs) external {

    }

    function initialize() public {
        //  Proxy contract implementation for gas savings.
        // 
    }

    function claim() public {
        //  allow individual 

    }
}