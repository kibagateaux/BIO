pragma solidity ^0.8.23;

library Utils { 
    struct AuctionMetadata {
        address launchCode; // approved template for fair token sales by BIO network 
        address giveToken;  // token being launched
        address wantToken;
        uint128 totalGive; // initial xDAO treasury (excl BIO reserves annd rewards)
        uint128 totalWant; // may be 0/max if open ended auction
        uint32  startTime; // unix timestamp or block depending on launchCode
        uint32  endTime; // unix timestamp or block depending on launchCode
        address manager; // who can update/close/etc auction after launch
        bytes customLaunchData; // (for launch provider if needed for auction settings or something)
    }
}