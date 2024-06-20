
import "forge-std/Test.sol";
import { Launchpad } from "src/Launchpad.sol";
import { BioBank } from "src/BioBank.sol";
import { XDAOToken } from "src/XDAOToken.sol";
import { ProRata } from "src/launchcodes/tpa.sol";

contract BaseLaunchpadTest is Test {
    Launchpad launchpad;
    BioBank bioBank;
    address operator;
    address bioNetwork;
    address curator;
    address xdao;
    XDAOToken bioToken;
    XDAOToken vbioToken;
    address curatorAuction;

    function setUp() public virtual {
        bioBank= new BioBank();
        operator = address(0x095);
        bioNetwork = address(0xb10);
        curator = address(0xc00);
        xdao = address(0xda0);
        bioToken =  new XDAOToken("BIO", "BIO");
        vbioToken = new XDAOToken("vBIO", "vBIO");
        curatorAuction = address(new ProRata());

        launchpad = new Launchpad(bioNetwork, address(bioBank), curatorAuction, 0, address(bioToken), address(vbioToken));

        vm.startPrank(bioNetwork);
        launchpad.setProgram(operator, true);
        launchpad.setLaunchCodes(curatorAuction, true);
        vm.stopPrank();
    }

    function test_constructor_setsInitData() public {
        assertEq(address(launchpad.bioBank()), address(bioBank));
        assertEq(launchpad.launchCodes(curatorAuction), true);
        assertEq(launchpad.curatorLaunchCode(), curatorAuction);
        assertEq(launchpad.operatorBIOReward(), 0);
        assertEq(address(launchpad.BIO()), address(bioToken));
        assertEq(address(launchpad.VBIO()), address(vbioToken));
        assertEq(launchpad.owner(), bioNetwork);
    }
}