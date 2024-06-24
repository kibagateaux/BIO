interface ITokenVesting {
    function balanceOf(address user) external returns(uint256);
    function grantRole(bytes32 role, address user) external;

    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revokable,
        uint256 _amount
    ) external;


}