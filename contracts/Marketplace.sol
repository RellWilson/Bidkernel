// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Escrow.sol";
import "./interfaces/IMarketplace.sol";

/// @title Marketplace
/// @notice BidKernel core protocol contract.
///         Sellers post listings; bidders submit bids backed by ETH.
///         When a seller accepts a bid an Escrow contract is deployed to hold
///         the funds until the buyer confirms delivery (or an arbiter resolves
///         a dispute).
contract Marketplace is IMarketplace {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error Marketplace__NotSeller();
    error Marketplace__NotBidder();
    error Marketplace__ListingNotActive();
    error Marketplace__BidNotPending();
    error Marketplace__BidNotAccepted();
    error Marketplace__BidBelowAskPrice();
    error Marketplace__ZeroBidAmount();
    error Marketplace__RefundFailed();

    // -------------------------------------------------------------------------
    // Data structures
    // -------------------------------------------------------------------------

    struct Listing {
        uint256      id;
        address      seller;
        string       title;
        string       metadataURI;
        uint256      askPrice;
        ListingStatus status;
        uint256[]    bidIds;
    }

    struct Bid {
        uint256   id;
        uint256   listingId;
        address   bidder;
        uint256   amount;
        BidStatus status;
        address   escrow;  // populated once the bid is accepted
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Protocol-wide arbiter that can resolve escrow disputes
    address public immutable arbiter;

    uint256 private _nextListingId;
    uint256 private _nextBidId;

    mapping(uint256 => Listing) private _listings;
    mapping(uint256 => Bid)     private _bids;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _arbiter Address of the trusted dispute arbiter
    constructor(address _arbiter) {
        arbiter = _arbiter;
    }

    // -------------------------------------------------------------------------
    // IMarketplace — listing management
    // -------------------------------------------------------------------------

    /// @inheritdoc IMarketplace
    function createListing(
        string calldata title,
        string calldata metadataURI,
        uint256 askPrice
    ) external override returns (uint256 listingId) {
        listingId = _nextListingId++;
        Listing storage l = _listings[listingId];
        l.id          = listingId;
        l.seller      = msg.sender;
        l.title       = title;
        l.metadataURI = metadataURI;
        l.askPrice    = askPrice;
        l.status      = ListingStatus.Active;
        emit ListingCreated(listingId, msg.sender, title, askPrice);
    }

    /// @inheritdoc IMarketplace
    function cancelListing(uint256 listingId) external override {
        Listing storage l = _listings[listingId];
        if (msg.sender != l.seller)              revert Marketplace__NotSeller();
        if (l.status != ListingStatus.Active)    revert Marketplace__ListingNotActive();
        l.status = ListingStatus.Cancelled;
        emit ListingCancelled(listingId, msg.sender);
    }

    // -------------------------------------------------------------------------
    // IMarketplace — bid management
    // -------------------------------------------------------------------------

    /// @inheritdoc IMarketplace
    function placeBid(uint256 listingId)
        external
        payable
        override
        returns (uint256 bidId)
    {
        Listing storage l = _listings[listingId];
        if (l.status != ListingStatus.Active)  revert Marketplace__ListingNotActive();
        if (msg.value == 0)                    revert Marketplace__ZeroBidAmount();
        if (msg.value < l.askPrice)            revert Marketplace__BidBelowAskPrice();

        bidId = _nextBidId++;
        Bid storage b  = _bids[bidId];
        b.id        = bidId;
        b.listingId = listingId;
        b.bidder    = msg.sender;
        b.amount    = msg.value;
        b.status    = BidStatus.Pending;

        l.bidIds.push(bidId);
        emit BidPlaced(listingId, bidId, msg.sender, msg.value);
    }

    /// @inheritdoc IMarketplace
    function acceptBid(uint256 listingId, uint256 bidId) external override {
        Listing storage l = _listings[listingId];
        Bid     storage b = _bids[bidId];

        if (msg.sender != l.seller)           revert Marketplace__NotSeller();
        if (l.status != ListingStatus.Active) revert Marketplace__ListingNotActive();
        if (b.status != BidStatus.Pending)    revert Marketplace__BidNotPending();

        b.status  = BidStatus.Accepted;
        l.status  = ListingStatus.Completed;

        // Deploy a dedicated Escrow contract funded with the bid amount
        Escrow escrow = new Escrow{value: b.amount}(
            b.bidder,
            l.seller,
            arbiter,
            address(this)
        );
        b.escrow = address(escrow);

        emit BidAccepted(listingId, bidId);
    }

    /// @inheritdoc IMarketplace
    function rejectBid(uint256 listingId, uint256 bidId) external override {
        Listing storage l = _listings[listingId];
        Bid     storage b = _bids[bidId];

        if (msg.sender != l.seller)        revert Marketplace__NotSeller();
        if (b.status != BidStatus.Pending) revert Marketplace__BidNotPending();

        b.status = BidStatus.Rejected;
        _refund(b.bidder, b.amount);
        emit BidRejected(listingId, bidId);
    }

    /// @inheritdoc IMarketplace
    function withdrawBid(uint256 listingId, uint256 bidId) external override {
        Bid storage b = _bids[bidId];

        if (msg.sender != b.bidder)        revert Marketplace__NotBidder();
        if (b.status != BidStatus.Pending) revert Marketplace__BidNotPending();

        b.status = BidStatus.Withdrawn;
        _refund(b.bidder, b.amount);
        emit BidWithdrawn(listingId, bidId);
    }

    /// @inheritdoc IMarketplace
    function confirmDelivery(uint256 listingId, uint256 bidId) external override {
        Bid storage b = _bids[bidId];

        if (msg.sender != b.bidder)          revert Marketplace__NotBidder();
        if (b.status != BidStatus.Accepted)  revert Marketplace__BidNotAccepted();

        Listing storage l = _listings[listingId];
        Escrow(b.escrow).releaseFor(msg.sender);

        emit TradeCompleted(listingId, bidId, l.seller, b.bidder, b.amount);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns the full data for a listing
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return _listings[listingId];
    }

    /// @notice Returns the full data for a bid
    function getBid(uint256 bidId) external view returns (Bid memory) {
        return _bids[bidId];
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _refund(address recipient, uint256 amount) internal {
        (bool ok, ) = recipient.call{value: amount}("");
        if (!ok) revert Marketplace__RefundFailed();
    }
}
