// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Escrow
/// @notice Minimal, trustless escrow used by the BidKernel Marketplace.
///         Funds are deposited by the buyer when a bid is accepted and can only
///         be released in three ways:
///           1. The buyer calls `release` directly → seller paid.
///           2. The marketplace calls `releaseFor(buyer)` after the buyer
///              confirms delivery through the Marketplace contract.
///           3. A dispute is resolved by the designated arbiter.
contract Escrow {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error Escrow__NotAuthorized();
    error Escrow__NotArbiter();
    error Escrow__InvalidRecipient();
    error Escrow__AlreadySettled();
    error Escrow__InsufficientFunds();
    error Escrow__TransferFailed();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event Deposited(address indexed buyer, uint256 amount);
    event Released(address indexed seller, uint256 amount);
    event Refunded(address indexed buyer, uint256 amount);

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;
    /// @notice The Marketplace contract that deployed this escrow.
    ///         It is allowed to call `releaseFor` once the buyer has confirmed
    ///         delivery through the Marketplace.
    address public immutable marketplace;
    uint256 public immutable depositAmount;
    bool    public settled;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    /// @param _buyer       Address that deposited funds (the winning bidder)
    /// @param _seller      Address that receives funds on delivery confirmation
    /// @param _arbiter     Trusted third party that can resolve disputes
    /// @param _marketplace Marketplace contract allowed to trigger release
    constructor(
        address _buyer,
        address _seller,
        address _arbiter,
        address _marketplace
    ) payable {
        if (msg.value == 0) revert Escrow__InsufficientFunds();
        buyer         = _buyer;
        seller        = _seller;
        arbiter       = _arbiter;
        marketplace   = _marketplace;
        depositAmount = msg.value;
        emit Deposited(_buyer, msg.value);
    }

    // -------------------------------------------------------------------------
    // External functions
    // -------------------------------------------------------------------------

    /// @notice Buyer confirms delivery directly; releases funds to seller.
    function release() external {
        if (msg.sender != buyer) revert Escrow__NotAuthorized();
        _settle(seller);
        emit Released(seller, depositAmount);
    }

    /// @notice Called by the Marketplace after verifying the buyer confirmed
    ///         delivery through the protocol.
    /// @param caller The address that called confirmDelivery on the Marketplace
    function releaseFor(address caller) external {
        if (msg.sender != marketplace) revert Escrow__NotAuthorized();
        if (caller != buyer)           revert Escrow__NotAuthorized();
        _settle(seller);
        emit Released(seller, depositAmount);
    }

    /// @notice Arbiter resolves a dispute in favour of either party.
    /// @param releaseTo Address that should receive the escrowed funds
    function resolveDispute(address releaseTo) external {
        if (msg.sender != arbiter) revert Escrow__NotArbiter();
        if (releaseTo != buyer && releaseTo != seller)
            revert Escrow__InvalidRecipient();
        bool toSeller = releaseTo == seller;
        _settle(releaseTo);
        if (toSeller) {
            emit Released(seller, depositAmount);
        } else {
            emit Refunded(buyer, depositAmount);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------
    function _settle(address recipient) internal {
        if (settled) revert Escrow__AlreadySettled();
        settled = true;
        (bool ok, ) = recipient.call{value: depositAmount}("");
        if (!ok) revert Escrow__TransferFailed();
    }
}
