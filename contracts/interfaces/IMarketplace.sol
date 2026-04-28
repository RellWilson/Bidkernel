// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMarketplace
/// @notice Interface for the BidKernel decentralized marketplace protocol
interface IMarketplace {
    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

    /// @notice Current status of a listing
    enum ListingStatus {
        Active,    // accepting bids
        Completed, // a bid was accepted and the trade settled
        Cancelled  // seller cancelled before any bid was accepted
    }

    /// @notice Current status of a bid
    enum BidStatus {
        Pending,   // awaiting seller response
        Accepted,  // seller accepted; funds held in escrow
        Rejected,  // seller declined
        Withdrawn  // bidder withdrew before acceptance
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        string  title,
        uint256 askPrice
    );

    event ListingCancelled(uint256 indexed listingId, address indexed seller);

    event BidPlaced(
        uint256 indexed listingId,
        uint256 indexed bidId,
        address indexed bidder,
        uint256 amount
    );

    event BidAccepted(uint256 indexed listingId, uint256 indexed bidId);

    event BidRejected(uint256 indexed listingId, uint256 indexed bidId);

    event BidWithdrawn(uint256 indexed listingId, uint256 indexed bidId);

    event TradeCompleted(
        uint256 indexed listingId,
        uint256 indexed bidId,
        address seller,
        address buyer,
        uint256 amount
    );

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @notice Create a new listing for a good or service
    /// @param title      Human-readable title for the listing
    /// @param metadataURI IPFS / Arweave URI pointing to extended metadata
    /// @param askPrice   Minimum acceptable price in wei (0 = open to any bid)
    /// @return listingId Unique identifier of the created listing
    function createListing(
        string calldata title,
        string calldata metadataURI,
        uint256 askPrice
    ) external returns (uint256 listingId);

    /// @notice Cancel an active listing (seller only, no accepted bids pending)
    /// @param listingId ID of the listing to cancel
    function cancelListing(uint256 listingId) external;

    /// @notice Submit a bid on an active listing
    /// @param listingId ID of the listing to bid on
    /// @return bidId Unique identifier of the created bid
    function placeBid(uint256 listingId) external payable returns (uint256 bidId);

    /// @notice Accept a pending bid; funds move into escrow
    /// @param listingId ID of the listing
    /// @param bidId     ID of the bid to accept
    function acceptBid(uint256 listingId, uint256 bidId) external;

    /// @notice Reject a pending bid; funds returned to bidder
    /// @param listingId ID of the listing
    /// @param bidId     ID of the bid to reject
    function rejectBid(uint256 listingId, uint256 bidId) external;

    /// @notice Withdraw a pending bid; funds returned to bidder
    /// @param listingId ID of the listing
    /// @param bidId     ID of the bid to withdraw
    function withdrawBid(uint256 listingId, uint256 bidId) external;

    /// @notice Buyer confirms receipt; escrow releases funds to seller
    /// @param listingId ID of the listing
    /// @param bidId     ID of the accepted bid
    function confirmDelivery(uint256 listingId, uint256 bidId) external;
}
