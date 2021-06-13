// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/InteractiveMaker.sol";


contract LimitOrderProtocolMock {
    function simulateNotify(address maker, address asset, uint256 amount, bytes32 orderHash) external {
        InteractiveMaker(maker).notifyFillOrder(asset, address(0x0), amount, 0, abi.encode(orderHash));
    }
}