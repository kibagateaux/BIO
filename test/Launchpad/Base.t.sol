
import "forge-std/Test.sol";

import { Launchpad } from "src/Launchpad.sol";
import { BioBank } from "src/BioBank.sol";
import { XDAOToken } from "src/XDAOToken.sol";
import { LaunchCodeFactory, ProRata } from "src/launchcodes/tpa.sol";

contract BaseLaunchpadTest is Test {
    Launchpad launchpad;
    BioBank bioBank;
    address operator;
    address bioNetwork;
    address curator;
    address xdao;
    XDAOToken bioToken;
    XDAOToken vbioToken;
    XDAOToken usdc;
    address curatorAuction;

    function setUp() public virtual {
        bioBank= new BioBank();
        operator = address(0x095);
        bioNetwork = address(0xb10);
        curator = address(0xc00);
        xdao = address(0xda0);
        bioToken =  new XDAOToken("BIO", "BIO");
        vbioToken = new XDAOToken("vBIO", "vBIO");
        usdc = new XDAOToken("USDC", "USDC");

        launchpad = new Launchpad(bioNetwork, address(bioBank), 0, address(bioToken), address(vbioToken));
        LaunchCodeFactory factory  = new LaunchCodeFactory();
        address prorata = address(new ProRata());
        factory.initialize(address(launchpad), prorata, prorata /* TODO vesting once integrated into repo */);
        curatorAuction = address(factory);

        vm.startPrank(bioNetwork);
        launchpad.setProgram(operator, true);
        launchpad.setLaunchCodes(curatorAuction, true, true);
        vm.stopPrank();
    }

    function test_constructor_setsInitData() public {
        assertEq(address(launchpad.bioBank()), address(bioBank));
        assertEq(launchpad.launchCodes(curatorAuction), true);
        assertEq(launchpad.curatorLaunchCode(), curatorAuction);
        assertEq(launchpad.operatorBIOReward(), 0);
        assertEq(address(launchpad.bio()), address(bioToken));
        assertEq(address(launchpad.vbio()), address(vbioToken));
        assertEq(launchpad.owner(), bioNetwork);
    }
}