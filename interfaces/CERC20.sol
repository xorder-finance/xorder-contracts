// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

abstract contract CErc20Interface {
    function mint(uint mintAmount) virtual external returns (uint);
    function redeem(uint redeemTokens) virtual external returns (uint);
    function redeemUnderlying(uint redeemAmount) virtual external returns (uint);
    function borrow(uint borrowAmount) virtual external returns (uint);
    function repayBorrow(uint repayAmount) virtual external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) virtual external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount) virtual external returns (uint);
    function balanceOf(address owner) virtual external view returns (uint);
    function balanceOfUnderlying(address owner) virtual external returns (uint);
}