
import "forge-std/Test.sol";

import { Launchpad } from "src/Launchpad.sol";
import { BioBank } from "src/BioBank.sol";
import { XDAOToken } from "src/XDAOToken.sol";
import { LaunchCodeFactory, ProRata } from "src/launchcodes/tpa.sol";
import { TokenVesting } from "@bio/vesting/TokenVesting.sol";
import { IERC20Metadata } from "@oz/token/ERC20/extensions/IERC20Metadata.sol";


contract BaseLaunchpadTest is Test {
    bytes32 public constant VESTING_ROLE = keccak256("VESTING_CREATOR_ROLE");
    Launchpad public launchpad;
    BioBank public bioBank;
    address public operator;
    address public bioNetwork;
    address public curator;
    address public xdao;
    XDAOToken public bio;
    TokenVesting public vbio;
    XDAOToken public usdc;
    address public curatorAuction;
    uint96 public operatorReward = 6900000;

    function setUp() public virtual {
        bioBank= new BioBank();
        operator = address(0x095);
        bioNetwork = address(0xb10);
        curator = address(0xc00);
        xdao = address(0xda0);
        bio =  new XDAOToken("BIO", "BIO");
        vbio = new TokenVesting(address(bio), "vBIO", "vBIO", address(bioNetwork));
        vbio.beginDefaultAdminTransfer(bioNetwork);
        usdc = new XDAOToken("USDC", "USDC");

        launchpad = new Launchpad(bioNetwork, address(bioBank), operatorReward, address(bio), address(vbio), address(usdc));
        LaunchCodeFactory factory  = new LaunchCodeFactory();
        address prorata = address(new ProRata());
        address vesting = address(new TokenVesting(address(bio), "xDAO", "vxDAO", address(bioNetwork)));
        factory.initialize(address(launchpad), prorata, vesting);
        curatorAuction = address(factory);

        skip(20);
        vm.startPrank(bioNetwork);
        vbio.acceptDefaultAdminTransfer();
        vbio.grantRole(VESTING_ROLE, address(bioNetwork));
        vbio.grantRole(VESTING_ROLE, address(launchpad));

        launchpad.setProgram(operator, true);
        launchpad.setLaunchCodes(curatorAuction, true, true);
        vm.stopPrank();
    }

    // function _mintVbio(address user, uint256 amount) internal {
    //     uint256 oldAmount = vbio.balanceOf(user);
    //     bytes256 balanceSlot;
    //     assembly {
    //         mstore(0x0c, _BALANCE_SLOT_SEED)
    //         mstore(0x00, owner)
    //         balanceSlot := keccak256(0x0c, 0x20)
    //     }
    //      bytes32 balanceSlot = keccak256(0x87a211a2, 0); // see solady erc20 for slot storage
    //      vm.store(address(vbio), balanceSlot, oldAmount + amount);
// }
    // function _mintVbio(address user, uint256 amount) internal {
    //     // Calculate the storage slot for `holdersVestedAmount[user]`
    //     // Slot calculation must consider the layout of the storage in the TokenVesting contract
    //     bytes32 slot = keccak256(abi.encode(user, uint256(5))); // Slot 2 is where `holdersVestedAmount` mapping starts
    //     emit log_named_uint("vbio slot", slot);
    //     // Load current amount from the storage
    //     uint256 currentAmount = uint256(vm.load(vbio, slot));
    //     emit log_named_uint("vbio slot balance", currentAmount);

    //     // Calculate new amount by adding the specified amount
    //     uint256 newAmount = currentAmount + amount;

    //     // Store the new amount back into the contract's storage
    //     vm.store(vbio, slot, bytes32(newAmount));
    //     emit log_named_uint("vbio slot new balance", uint256(vm.load(vbio, slot)));
    // }
    function _mintVbio(address user, uint256 amount) internal {
        vm.startPrank(bioNetwork);
        bio.mint(address(vbio), amount);
        vbio.createVestingSchedule(user, block.timestamp, 0, block.timestamp + 7 days, 60, false, amount);
        vm.stopPrank();
    }


    // function _setAppStatus(uint64 appID, Launchpad.APPLICATION_STATUS status) internal {
    //      bytes32 slot = keccak256(abi.encode(appID, 0));
    //      vm.store(address(vbio), 0x87a211a2, uint256(status)); // see solady erc20 for slot seed
    // }

    function test_constructor_setsInitData() public {
        assertEq(address(launchpad.bioBank()), address(bioBank));
        assertEq(launchpad.launchCodes(curatorAuction), true);
        assertEq(launchpad.curatorLaunchCode(), curatorAuction);
        assertEq(launchpad.operatorBIOReward(), operatorReward);
        assertEq(address(launchpad.bio()), address(bio));
        assertEq(address(launchpad.vbio()), address(vbio));
        assertEq(launchpad.owner(), bioNetwork);
    }

    function  test__encodeID_storesAppIdAndCurator(uint96 id, address staker) public {
        // emit log_named_uint("to encode id 1 ", id);
        // emit log_named_address("to encode staker 1 ", staker);
        // emit log_named_uint("encoded id 1 ", encodeTest1(id, staker));
        // emit log_named_bytes32("encoded id 1 ", bytes32(encodeTest1(id, staker)));
        // uint256 id1 = encodeTest1(id, staker);
        // assertEq(id1, encodedId);
        uint256 id2 = encodeTest2(id, staker);
        // emit log_named_uint("encoded id 2 ", encodeTest1(id, staker));
        emit log_named_bytes32("encoded id 2 ", bytes32(id2));

        // emit log_named_uint("encoded id 2 ", encodeTest1(id, staker));
        
        // uint256 encodedAddy = uint256(uint160(staker) << 160);
        // uint256 encodedID = encodeTest1(id, staker);

        // uint96 id1 = uint96(0);
        // uint160 id2 = uint160(staker);

        // // Shift the second address value to the left by 160 bits (20 bytes)
        // // uint96 encodedValue = uint96(id1 << 160);
        // // Add the first address value to the encoded value

        // // Check first 12 bytes (uint96)
        assertEq(uint96(id2 >> 160), id, "First 12 bytes should match uint96");
        
        // // Check last 20 bytes (address)
        assertEq(address(uint160(id2)), staker, "Last 20 bytes should match address");

        uint256 encodedID = launchpad._encodeID(id, staker);
        assertEq(id2, encodedID);
    }

    function encodeTest1(uint96 appID, address curator) public  returns (uint256) {
        bytes32 result;
        
        assembly {
            // Encode uint96 into the first 12 bytes
            result := appID
            
            // Encode address into the last 20 bytes
            // let addrBytes := and(curator, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            result := or(result, shl(96, curator))
        }

        emit log_named_bytes32("encode test 1 byte", result);
        emit log_named_uint("encode test 1 uint", uint256(result));
        return uint256(result);
    }


    function encodeTest2(uint96 appID, address curator) public  returns (uint256) {
        bytes32 result;
        
        assembly {
            // Encode uint96 into the first 12 bytes
            // result := appID
            
            // Encode address into the last 20 bytes
            // let addrBytes := and(curator, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            result := shl(160, appID)
            result := or(result, shl(0, curator))
        }

        emit log_named_bytes32("encode test 2 byte", result);
        emit log_named_uint("encode test 2 uint", uint256(result));
        return uint256(result);
    }

}