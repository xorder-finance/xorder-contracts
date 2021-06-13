// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/CERC20.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/LimitOrderProtocol.sol";


contract PPContract is Ownable {
    using SafeERC20 for IERC20;

    event OrderCreated(address indexed maker, bytes32 orderHash, uint256 amount);
    event OrderCancelled(bytes32 orderHash);
    event OrderNotified(bytes32 orderHash, uint256 amount);
    event OrderWithdrawed(bytes32 orderHash, uint256 amount);

    struct Order {
        address user;
        address asset;
        uint256 remaining;
        uint256 cRemaining;
        uint256 toWithdraw;
    }

    ComptrollerInterface immutable comptroller;
    address immutable limitOrderProtocol;
    address immutable COMP;
    
    mapping(address => address) private cTokens; // token => cToken
    address[] public tokens; // supported tokens array
    mapping(bytes32 => Order) private orders; // orderHash => Order

    uint8 constant MAX_UNITS = 100;
    uint8 constant USER_FEE_UNIT = 97;

    constructor(ComptrollerInterface _comptroller, address _comp, address _limitOrderProtocol) {
        comptroller = _comptroller;
        limitOrderProtocol = _limitOrderProtocol;
        COMP = _comp;
    }
    
    /// @notice callback from limit order protocol, executes on order fill
    function notifyFillOrder(
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        bytes memory interactiveData // abi.encode(orderHash)
    ) external {
        require(msg.sender == limitOrderProtocol, "only limitOrderProtocol can exec callback");
        makerAsset;
        takingAmount;
        bytes32 orderHash = abi.decode(interactiveData, (bytes32));
        _withdrawCompound(orderHash, makingAmount, false); // withdraw tokens from compound, send fees to user
        IERC20(makerAsset).safeApprove(limitOrderProtocol, makingAmount); // approve tokens for limitOrderProtocol
        emit OrderNotified(orderHash, makingAmount);
    }

    /// @notice sends user tokens to Compound and stores asset, amount, user
    /// called after order creation
    function createOrder(bytes32 orderHash, address asset, uint256 amount) external {
        require(orders[orderHash].user == address(0x0), "order is already exist");
        require(cTokens[asset] != address(0x0), "unsupported asset");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(cTokens[asset], amount);
        CErc20Interface cToken = CErc20Interface(cTokens[asset]);
        uint256 cBalanceBefore = cToken.balanceOf(address(this));

        require(cToken.mint(amount) == 0, "comptroller mint error"); // send tokens to compound

        uint256 cBalanceAfter = cToken.balanceOf(address(this));
        orders[orderHash].user = msg.sender;
        orders[orderHash].asset = asset;
        orders[orderHash].remaining = amount; // unfilled amount of order
        orders[orderHash].cRemaining = cBalanceAfter - cBalanceBefore; // user ctokens remaining
        emit OrderCreated(msg.sender, orderHash, amount);
    }

    /// @notice withdraws all user funds from Compound, sends funds + fee to user
    function cancelOrder(bytes32 orderHash, LimitOrderProtocol.LOPOrder memory order) external {
        require(orders[orderHash].user != msg.sender, "invalid user or order not exist");
        
        LimitOrderProtocol(limitOrderProtocol).cancelOrder(order); // cancel in protocol
        _withdrawCompound(orderHash, orders[orderHash].remaining, true); // withdraw all funds from compound
        delete orders[orderHash];
        emit OrderCancelled(orderHash);
    }

    /// @notice send all free assets + COMP(included) to Compound
    function makeMoney() external {
        comptroller.claimComp(address(this));
        // iterate through all tokens trying to find free money
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }
            // send them to work in Compound
            require(CErc20Interface(cTokens[tokens[i]]).mint(balance) == 0, "compound mint error"); 
        }
    }

    function init() onlyOwner external {
        if (tokens.length > 0) {
            return;
        }

        address[] memory _cTokens = comptroller.getAllMarkets(); // get all cTokens and fill mapping ->

        for (uint256 i = 0; i < _cTokens.length; i++) { // <- underlying => cToken
            CErc20Interface ctoken = CErc20Interface(_cTokens[i]);
            if (keccak256(abi.encode(ctoken.name())) == keccak256(abi.encode("Compound ETH"))) { // ignore cETH
                continue;
            }
            if (keccak256(abi.encode(ctoken.name())) == keccak256(abi.encode("Compound Ether"))) { // ignore cETH
                continue;
            }
            address token = ctoken.underlying();
            tokens.push(token);
            cTokens[token] = _cTokens[i];
        }
    }

    /// @notice withdraw funds from orders with hashes in args
    function withdraw(bytes32[] memory ordersHashes) external {
        for (uint256 i = 0; i < ordersHashes.length; i++) {
            Order storage order = orders[ordersHashes[i]];
            require(order.user == msg.sender, "invalid user/order not exist/order withdrawed");
            if (order.toWithdraw == 0) {
                continue;
            }
            IERC20(order.asset).transfer(msg.sender, order.toWithdraw);
            emit OrderWithdrawed(ordersHashes[i], order.toWithdraw);
            delete orders[ordersHashes[i]];
        }
    }

    /// @notice withdraws *amount* underlying from + fee from Compound, sends to user funds
    function _withdrawCompound(bytes32 orderHash, uint256 amount, bool cancel) internal {
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

        uint256 toTransfer = userFee; // if order is not cancelled then transer just fee
        if (cancel) {
            toTransfer += amountToWithdraw;
        } else {
            order.toWithdraw += amountToWithdraw; // user will claim his funds later, contract will send amount tokens to taker
        }
        IERC20(asset).safeTransfer(user, toTransfer); // send to user fee and amount (if order cancelled)
    }

    /// @notice mock
    function isValidSignature(bytes32 hash, bytes memory signature) public view returns(bytes4) {
        return this.isValidSignature.selector;
    }
}