// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {SimpleERC20} from "./helpers/SimpleERC20.sol";
import {DemoWallet} from "../src/DemoWallet.sol";
import {WaxLib as WL} from "../src/WaxLib.sol";
import {DeployTester} from "./helpers/DeployTester.sol";

contract DemoWalletTest is Test {
    SimpleERC20 token = new SimpleERC20(
        "Token",
        "TOK",
        address(this),
        type(uint256).max
    );

    function test_send_eth() public {
        DemoWallet w = new DemoWallet(address(this));
        vm.deal(address(w), 100 ether);

        WL.Action[] memory actions = new WL.Action[](1);

        actions[0] = WL.Action({
            to: address(0),
            value: 1 ether,
            data: new bytes(0)
        });

        w.perform(actions);

        assertEq(address(w).balance, 99 ether);
        assertEq(address(0).balance, 1 ether);
    }

    function test_call() public {
        DemoWallet w = new DemoWallet(address(this));
        token.transfer(address(w), 100e18);

        WL.Action[] memory actions = new WL.Action[](1);

        actions[0] = WL.Action({
            to: address(token),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(1),
                1e18
            )
        });

        w.perform(actions);

        assertEq(token.balanceOf(address(w)), 99e18);
        assertEq(token.balanceOf(address(1)), 1e18);
    }

    function test_deploy() public {
        DemoWallet w = new DemoWallet(address(this));
        vm.deal(address(w), 100 ether);

        WL.Action[] memory actions = new WL.Action[](1);

        actions[0] = WL.Action({
            to: WL.contractCreationAddress,
            value: 1 ether,
            data: abi.encodePacked(
                type(DeployTester).creationCode,
                abi.encode(123, address(456))
            )
        });

        bytes[] memory results = w.perform(actions);
        DeployTester dt = abi.decode(results[0], (DeployTester));

        assertEq(address(dt).balance, 1 ether);
        assertEq(dt.x(), 123);
        assertEq(dt.addr(), address(456));
    }
}