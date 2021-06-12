// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/Comptroller.sol";

contract PPContract is Ownable {
    using SafeERC20 for IERC20;

    event OrderCreated(address indexed maker, bytes32 orderHash, uint256 amount);
    event OrderCancelled(bytes32 orderHash);
    // event OrderNotfified(bytes32 orderHash);

    struct Order {
        address user;
        address asset;
        uint256 remaining;
        uint256 cRemaining;
    }

    ComptrollerInterface constant compound = ComptrollerInterface(0x3ef51736315F52d568D6D2cf289419b9CfffE782);
    address constant limitOrderProtocol = 0x3ef51736315F52d568D6D2cf289419b9CfffE782;

    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant cWBTC = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4;
    address constant cCOMP = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4;
    
    mapping(address => address) private cTokens;
    mapping(bytes32 => Order) private orders;

    uint8 constant MAX_UNITS = 100;
    uint8 constant USER_FEE_UNIT = 97;

    constructor() {
        cTokens[DAI] = cDAI;
        cTokens[WBTC] = cWBTC;
        cTokens[COMP] = cCOMP;
    }
 
    function createOrder(bytes32 orderHash, address asset, uint256 amount) external {
        require(orders[orderHash].user == address(0x0), "order is already exist");
        require(cTokens[asset] != address(0x0), "unsupported assert");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        address cToken = cTokens[asset];
        IERC20(asset).safeApprove(cToken, amount);
        uint256 cBalanceBefore = CErc20Interface(cToken).balanceOf(address(this));
        require(CErc20Interface(cToken).mint(amount) != 0, "compound mint error");
        uint256 cBalanceAfter = CErc20Interface(cToken).balanceOf(address(this));
        orders[orderHash].user = msg.sender;
        orders[orderHash].asset = asset;
        orders[orderHash].remaining = amount;
        orders[orderHash].cRemaining = cBalanceAfter - cBalanceBefore;
        emit OrderCreated(msg.sender, orderHash, amount);
    }

    function cancelOrder(bytes32 orderHash) external {
        require(orders[orderHash].user != address(0x0), "order should exist");
        // cancel in LMO protocol
        _withdrawCompound(orderHash, orders[orderHash].remaining);
        delete orders[orderHash];
        emit OrderCancelled(orderHash);
    }

    function _withdrawCompound(bytes32 orderHash, uint256 amount) internal {
        Order storage order = orders[orderHash];
        address user = order.user;
        require(user != address(0x0), "order should exist");
        require(amount <= order.remaining, "withdraw amount exceeds user balance");
        if (amount == 0) {
            return;
        }
        CErc20Interface cToken = CErc20Interface(cTokens[order.asset]);
        uint256 remaining = order.remaining;
        uint256 amountToWithdraw = amount;
        address asset = order.asset;
        uint256 cAmount = order.cRemaining * amountToWithdraw / remaining;
        order.remaining -= amountToWithdraw;
        order.cRemaining -= cAmount;

        require(cToken.redeem(cAmount) == 0, "compound redeem error");

        uint256 underlyingBefore = IERC20(asset).balanceOf(address(this));
        uint256 compBefore = IERC20(COMP).balanceOf(address(this));
        // address[1] memory tokens = new address[1](cToken);
        address[] memory ctokens = new address[](1);
        ctokens[0] = address(cToken);
        compound.claimComp(address(this), ctokens);

        uint256 underlyingAfter = IERC20(asset).balanceOf(address(this));
        uint256 compAfter = IERC20(COMP).balanceOf(address(this));
        uint256 claimedUnderlying = underlyingAfter - underlyingBefore;
        uint256 claimedComp = compAfter - compBefore;
        uint256 userFee = (claimedUnderlying - amountToWithdraw) * USER_FEE_UNIT / MAX_UNITS;
 
        IERC20(asset).safeTransfer(user, amountToWithdraw + userFee);

        if (claimedComp == 0) {
            return;
        }
        uint256 userCompFee = claimedComp * USER_FEE_UNIT / MAX_UNITS;

        IERC20(COMP).safeTransfer(user, userCompFee);
    }

}