// called during Launch(). 
// Gives standard inputs with one custom field for data for launchcode
// validate data going in
// only for public launch. staker launch is automated in launchpad

interface LaunchCode {
    function launch(address governance, uint256 initial, uint256 totalSupply) returns(bool);
    // check if custom launch template data is valid
    function validateData(bytes[] inputs) returns(bool);
}