// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

struct RiskScore {
    uint32 daysPastDue;
    uint32 advanceRate;
    uint32 penaltyRate;
    uint32 interestRate;
    uint32 probabilityOfDefault;
    uint32 lossGivenDefault;
    uint32 writeOffAfterGracePeriod;
    uint32 gracePeriod;
    uint32 collectionPeriod;
    uint32 writeOffAfterCollectionPeriod;
    uint32 discountRate;
}


// uint32 advanceRate;
//     uint32 penaltyRate;
//     uint32 interestRate;
//     uint32 probabilityOfDefault;
//     uint32 lossGivenDefault;
//     uint32 writeOffAfterGracePeriod;
//     uint32 gracePeriod;
//     uint32 collectionPeriod;
//     uint32 writeOffAfterCollectionPeriod;
//     uint32 discountRate;