import { ERC20 } from "solady/tokens/ERC20.sol";

contract XDAOToken is ERC20 {
    string private NAME;
    string private SYMBOL;

    constructor(string memory _name, string memory _symbol) {
        NAME = _name;
        SYMBOL = _symbol;
    }

    function name() public view virtual override returns (string memory) {
        return NAME;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual override returns (string memory) {
       return SYMBOL;
    }

    function mint(address to, uint256 amount) public {
        // TODO role controls
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) public {
        // TODO role controls
        _burn(from, amount);
    }

}