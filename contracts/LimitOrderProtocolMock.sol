// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/InteractiveMaker.sol";


contract LimitOrderProtocolMock {
    function simulateNotify(address maker, address asset, uint256 amount, bytes32 orderHash) external {
        InteractiveMaker(maker).notifyFillOrder(asset, address(0x0), amount, 0, abi.encode(orderHash));
    }
}