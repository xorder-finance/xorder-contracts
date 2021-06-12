// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ComptrollerInterface {
    function getAllMarkets() external view returns (address[] memory);
    function claimComp(address holder) external;
    function claimComp(address holder, address[] memory cTokens) external;
}
