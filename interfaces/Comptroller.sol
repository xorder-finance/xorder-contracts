// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract ComptrollerInterface {
    function getAllMarkets() virtual public view returns (address[] memory);
    function claimComp(address holder) virtual public;
    function claimComp(address holder, address[] memory cTokens) virtual public;
}
