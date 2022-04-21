// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../interfaces/ILoanRegistry.sol';
import '../../../interfaces/ILoanInterestTermsContract.sol';
import '../../../interfaces/IUntangledERC721.sol';

/**
 * LoanAssetToken: The representative for ownership of a Loan
 */
contract LoanAssetToken is IUntangledERC721 {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry,
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) public override initializer {
        __ERC721PresetMinterPauserAutoId_init(name, symbol, baseTokenURI);
    }

    function getExpectedRepaymentValues(uint256 tokenId, uint256 timestamp)
        public
        view
        returns (uint256 expectedPrincipal, uint256 expectedInterest)
    {
        bytes32 agreementId = bytes32(tokenId);
        (expectedPrincipal, expectedInterest) = registry.getLoanInterestTermsContract().getExpectedRepaymentValues(
            agreementId,
            timestamp
        );
    }

    function getExpirationTimestamp(uint256 _tokenId) public view returns (uint256) {
        return registry.getLoanRegistry().getExpirationTimestamp(bytes32(_tokenId));
    }

    function getRiskScore(uint256 _tokenId) public view returns (uint8) {
        return registry.getLoanRegistry().getRiskScore(bytes32(_tokenId));
    }

    function getAssetPurpose(uint256 _tokenId) public view returns (uint8) {
        return registry.getLoanRegistry().getAssetPurpose(bytes32(_tokenId));
    }

    function getInterestRate(uint256 _tokenId) public view returns (uint256 beneficiary) {
        return registry.getLoanInterestTermsContract().getInterestRate(bytes32(_tokenId));
    }

    function getTotalExpectedRepaymentValue(uint256 agreementId, uint256 timestamp)
        public
        view
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(agreementId, timestamp);
        expectedRepaymentValue = principalAmount.add(interestAmount);
    }
}
