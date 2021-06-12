// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface CErc20Interface {
    function name() external view returns (string memory);
    function underlying() external view returns (address);
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount) external returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function balanceOfUnderlying(address owner) external view returns (uint);
}