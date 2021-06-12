// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

abstract contract ComptrollerInterface {
        /**
     * @notice Claim all the comp accrued by holder in the specified markets
     * @param holder The address to claim COMP for
     * @param cTokens The list of markets to claim COMP in
     */
    function claimComp(address holder, address[] memory cTokens) virtual public;
}
