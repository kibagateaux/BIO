// called during Launch(). 
// Gives standard inputs with one custom field for data for launchcode
// validate data going in
// only for public launch. staker launch is automated in launchpad

interface ILaunchCode {
    // creates the public auction for 
    function launch(address governance, uint256 tokensAuctioned, uint32 startDate, uint32 endDate) external returns(address);
    // check if custom launch template data is valid
    function validateData(bytes[] calldata inputs) external;
}