// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/Comptroller.sol";


contract PPContract is Ownable {
    using SafeERC20 for IERC20;

    event OrderCreated(address indexed maker, bytes32 orderHash, uint256 amount);
    event OrderCancelled(bytes32 orderHash);
    event OrderNotfified(bytes32 orderHash, uint256 amount, bool filled);

    struct Order {
        address user;
        address asset;
        uint256 remaining;
        uint256 cRemaining;
    }

    struct LOPOrder {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        bytes makerAssetData; // (transferFrom.selector, signer, ______, makerAmount, ...)
        bytes takerAssetData; // (transferFrom.selector, sender, signer, takerAmount, ...)
        bytes getMakerAmount; // this.staticcall(abi.encodePacked(bytes, swapTakerAmount)) => (swapMakerAmount)
        bytes getTakerAmount; // this.staticcall(abi.encodePacked(bytes, swapMakerAmount)) => (swapTakerAmount)
        bytes predicate;      // this.staticcall(bytes) => (bool)
        bytes permit;         // On first fill: permit.1.call(abi.encodePacked(permit.selector, permit.2))
        bytes interaction;
    }

    ComptrollerInterface immutable comptroller;
    address immutable COMP;
    
    mapping(address => address) private cTokens;
    mapping(bytes32 => Order) private orders;

    uint8 constant MAX_UNITS = 100;
    uint8 constant USER_FEE_UNIT = 97;

    constructor(ComptrollerInterface _comptroller, address _comp) {
        comptroller = _comptroller;
        COMP = _comp;
        address[] memory _cTokens = _comptroller.getAllMarkets(); // get all cTokens and fill mapping ->
        for (uint256 i = 0; i < _cTokens.length; i++) { // <- underlying => cToken
            cTokens[CErc20Interface(_cTokens[i]).underlying()] = _cTokens[i];
        }
    }
    
    /// @notice callback from limit order protocol, executes on order fill
    function notifyFillOrder(
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes memory interactiveData // abi.encode(keccak256(abi.encode(order)))
    ) external {
        bytes32 orderHash = abi.decode(interactiveData, (bytes32));
        _withdrawCompound(orderHash, takingAmount);
        bool filled = false;
        if (orders[orderHash].remaining == 0) {
            filled = true;
            delete orders[orderHash];
        }
        emit OrderNotfified(orderHash, takingAmount, filled);
    }

    /// @notice sends user tokens to Compound and stores asset, amount, user
    /// called after order creation
    function createOrder(LOPOrder memory order, uint256 amount) external {
        bytes32 orderHash = keccak256(abi.encode(order));
        address asset = order.makerAsset;
        require(orders[orderHash].user == address(0x0), "order is already exist");
        require(cTokens[asset] != address(0x0), "unsupported assert");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        address cToken = cTokens[asset];
        IERC20(asset).safeApprove(cToken, amount);
        uint256 cBalanceBefore = CErc20Interface(cToken).balanceOf(address(this));

        require(CErc20Interface(cToken).mint(amount) != 0, "comptroller mint error"); // send tokens to compound

        uint256 cBalanceAfter = CErc20Interface(cToken).balanceOf(address(this));
        orders[orderHash].user = msg.sender;
        orders[orderHash].asset = asset;
        orders[orderHash].remaining = amount; // unfilled amount of order
        orders[orderHash].cRemaining = cBalanceAfter - cBalanceBefore; // user ctokens remaining
        emit OrderCreated(msg.sender, orderHash, amount);
    }

    /// @notice withdraws all user funds from Compound, sends funds + fee to user
    /// called before cancelling order on limit order protocol 
    function cancelOrder(LOPOrder memory order) external {
        bytes32 orderHash = keccak256(abi.encode(order));
        require(orders[orderHash].user != address(0x0), "order should exist");
        
        _withdrawCompound(orderHash, orders[orderHash].remaining); // withdraw all funds from compound
        delete orders[orderHash];
        emit OrderCancelled(orderHash);
    }

    /// @notice withdraws *amount* underlying from + fee from Compound, sends to user funds
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

        // calculate amount to withdraw in cTokens, amount / remaining - fraction
        uint256 cAmount = order.cRemaining * amountToWithdraw / remaining; // cRemaining - remaining minted cTokens
        uint256 underlyingBefore = IERC20(asset).balanceOf(address(this));
        order.remaining -= amountToWithdraw;
        order.cRemaining -= cAmount;

        require(cToken.redeem(cAmount) == 0, "comptroller redeem error");

        uint256 underlyingAfter = IERC20(asset).balanceOf(address(this));
        uint256 claimedUnderlying = underlyingAfter - underlyingBefore;
        uint256 userFee = (claimedUnderlying - amountToWithdraw) * USER_FEE_UNIT / MAX_UNITS;
 
        IERC20(asset).safeTransfer(user, amountToWithdraw + userFee); // send to user amount + fee (earned in Compound)
    }
}