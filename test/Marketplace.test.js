const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Marketplace", function () {
  let marketplace;
  let arbiter, seller, buyer, other;

  const TITLE        = "Vintage guitar";
  const METADATA_URI = "ipfs://QmExampleHash";
  const ASK_PRICE    = ethers.parseEther("0.5");

  beforeEach(async function () {
    [arbiter, seller, buyer, other] = await ethers.getSigners();

    const Marketplace = await ethers.getContractFactory("Marketplace");
    marketplace = await Marketplace.deploy(arbiter.address);
  });

  // ---------------------------------------------------------------------------
  // Listings
  // ---------------------------------------------------------------------------

  describe("createListing", function () {
    it("emits ListingCreated and stores the listing correctly", async function () {
      await expect(
        marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE)
      )
        .to.emit(marketplace, "ListingCreated")
        .withArgs(0, seller.address, TITLE, ASK_PRICE);

      const listing = await marketplace.getListing(0);
      expect(listing.seller).to.equal(seller.address);
      expect(listing.title).to.equal(TITLE);
      expect(listing.askPrice).to.equal(ASK_PRICE);
      expect(listing.status).to.equal(0); // Active
    });

    it("increments listing IDs for each new listing", async function () {
      await marketplace.connect(seller).createListing("Item A", METADATA_URI, 0);
      await marketplace.connect(seller).createListing("Item B", METADATA_URI, 0);

      const listingA = await marketplace.getListing(0);
      const listingB = await marketplace.getListing(1);
      expect(listingA.title).to.equal("Item A");
      expect(listingB.title).to.equal("Item B");
    });
  });

  describe("cancelListing", function () {
    beforeEach(async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
    });

    it("seller can cancel an active listing", async function () {
      await expect(marketplace.connect(seller).cancelListing(0))
        .to.emit(marketplace, "ListingCancelled")
        .withArgs(0, seller.address);

      const listing = await marketplace.getListing(0);
      expect(listing.status).to.equal(2); // Cancelled
    });

    it("non-seller cannot cancel", async function () {
      await expect(marketplace.connect(other).cancelListing(0))
        .to.be.revertedWithCustomError(marketplace, "Marketplace__NotSeller");
    });

    it("cannot cancel an already-cancelled listing", async function () {
      await marketplace.connect(seller).cancelListing(0);
      await expect(marketplace.connect(seller).cancelListing(0))
        .to.be.revertedWithCustomError(marketplace, "Marketplace__ListingNotActive");
    });
  });

  // ---------------------------------------------------------------------------
  // Bids
  // ---------------------------------------------------------------------------

  describe("placeBid", function () {
    beforeEach(async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
    });

    it("emits BidPlaced and records the bid", async function () {
      await expect(
        marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE })
      )
        .to.emit(marketplace, "BidPlaced")
        .withArgs(0, 0, buyer.address, ASK_PRICE);

      const bid = await marketplace.getBid(0);
      expect(bid.bidder).to.equal(buyer.address);
      expect(bid.amount).to.equal(ASK_PRICE);
      expect(bid.status).to.equal(0); // Pending
    });

    it("reverts when bid is below ask price", async function () {
      const lowBid = ethers.parseEther("0.1");
      await expect(
        marketplace.connect(buyer).placeBid(0, { value: lowBid })
      ).to.be.revertedWithCustomError(marketplace, "Marketplace__BidBelowAskPrice");
    });

    it("reverts when bid amount is zero", async function () {
      await expect(
        marketplace.connect(buyer).placeBid(0, { value: 0 })
      ).to.be.revertedWithCustomError(marketplace, "Marketplace__ZeroBidAmount");
    });

    it("reverts on a cancelled listing", async function () {
      await marketplace.connect(seller).cancelListing(0);
      await expect(
        marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE })
      ).to.be.revertedWithCustomError(marketplace, "Marketplace__ListingNotActive");
    });
  });

  describe("acceptBid", function () {
    beforeEach(async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
      await marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE });
    });

    it("emits BidAccepted and deploys escrow", async function () {
      await expect(marketplace.connect(seller).acceptBid(0, 0))
        .to.emit(marketplace, "BidAccepted")
        .withArgs(0, 0);

      const bid = await marketplace.getBid(0);
      expect(bid.status).to.equal(1); // Accepted
      expect(bid.escrow).to.not.equal(ethers.ZeroAddress);
    });

    it("escrow contract holds the bid amount", async function () {
      await marketplace.connect(seller).acceptBid(0, 0);
      const bid = await marketplace.getBid(0);
      const escrowBalance = await ethers.provider.getBalance(bid.escrow);
      expect(escrowBalance).to.equal(ASK_PRICE);
    });

    it("non-seller cannot accept bid", async function () {
      await expect(marketplace.connect(other).acceptBid(0, 0))
        .to.be.revertedWithCustomError(marketplace, "Marketplace__NotSeller");
    });
  });

  describe("rejectBid", function () {
    beforeEach(async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
      await marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE });
    });

    it("refunds the bidder and emits BidRejected", async function () {
      const balanceBefore = await ethers.provider.getBalance(buyer.address);
      await marketplace.connect(seller).rejectBid(0, 0);
      const balanceAfter = await ethers.provider.getBalance(buyer.address);

      expect(balanceAfter - balanceBefore).to.equal(ASK_PRICE);
      await expect(marketplace.connect(seller).rejectBid(0, 0)).to.be.revertedWithCustomError(
        marketplace,
        "Marketplace__BidNotPending"
      );
    });

    it("non-seller cannot reject", async function () {
      await expect(marketplace.connect(other).rejectBid(0, 0))
        .to.be.revertedWithCustomError(marketplace, "Marketplace__NotSeller");
    });
  });

  describe("withdrawBid", function () {
    beforeEach(async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
      await marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE });
    });

    it("refunds the bidder and emits BidWithdrawn", async function () {
      const balanceBefore = await ethers.provider.getBalance(buyer.address);
      const tx = await marketplace.connect(buyer).withdrawBid(0, 0);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(buyer.address);

      expect(balanceAfter + gasUsed - balanceBefore).to.equal(ASK_PRICE);
    });

    it("non-bidder cannot withdraw", async function () {
      await expect(marketplace.connect(other).withdrawBid(0, 0))
        .to.be.revertedWithCustomError(marketplace, "Marketplace__NotBidder");
    });
  });

  // ---------------------------------------------------------------------------
  // Full happy-path: list → bid → accept → confirm delivery
  // ---------------------------------------------------------------------------

  describe("confirmDelivery (full trade flow)", function () {
    it("releases escrow funds to the seller", async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
      await marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE });
      await marketplace.connect(seller).acceptBid(0, 0);

      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);

      const tx = await marketplace.connect(buyer).confirmDelivery(0, 0);
      await expect(tx)
        .to.emit(marketplace, "TradeCompleted")
        .withArgs(0, 0, seller.address, buyer.address, ASK_PRICE);

      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(ASK_PRICE);
    });

    it("non-buyer cannot confirm delivery", async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
      await marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE });
      await marketplace.connect(seller).acceptBid(0, 0);

      await expect(marketplace.connect(other).confirmDelivery(0, 0))
        .to.be.revertedWithCustomError(marketplace, "Marketplace__NotBidder");
    });
  });

  // ---------------------------------------------------------------------------
  // Escrow — dispute resolution
  // ---------------------------------------------------------------------------

  describe("Escrow dispute resolution", function () {
    let escrow;

    beforeEach(async function () {
      await marketplace.connect(seller).createListing(TITLE, METADATA_URI, ASK_PRICE);
      await marketplace.connect(buyer).placeBid(0, { value: ASK_PRICE });
      await marketplace.connect(seller).acceptBid(0, 0);

      const bid = await marketplace.getBid(0);
      const Escrow = await ethers.getContractFactory("Escrow");
      escrow = Escrow.attach(bid.escrow);
    });

    it("arbiter can resolve dispute in favour of seller", async function () {
      const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
      await escrow.connect(arbiter).resolveDispute(seller.address);
      const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(ASK_PRICE);
    });

    it("arbiter can resolve dispute in favour of buyer", async function () {
      const buyerBalanceBefore = await ethers.provider.getBalance(buyer.address);
      await escrow.connect(arbiter).resolveDispute(buyer.address);
      const buyerBalanceAfter = await ethers.provider.getBalance(buyer.address);
      expect(buyerBalanceAfter - buyerBalanceBefore).to.equal(ASK_PRICE);
    });

    it("non-arbiter cannot resolve dispute", async function () {
      await expect(escrow.connect(other).resolveDispute(seller.address))
        .to.be.revertedWithCustomError(escrow, "Escrow__NotArbiter");
    });

    it("cannot settle twice", async function () {
      await escrow.connect(arbiter).resolveDispute(seller.address);
      await expect(escrow.connect(arbiter).resolveDispute(seller.address))
        .to.be.revertedWithCustomError(escrow, "Escrow__AlreadySettled");
    });
  });
});
