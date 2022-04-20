// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/INoteTokenFactory.sol';

contract NoteTokenFactory is UntangledBase, INoteTokenFactory {
    using ConfigHelper for Registry;

    modifier onlySecuritizationManager() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'SecuritizationPool: Only SecuritizationManager'
        );
        _;
    }

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(address(this));

        registry = _registry;
    }

    function changeTokenController(address tokenAddress, address newController)
        external
        override
        onlySecuritizationManager
    {
        NoteToken token = NoteToken(tokenAddress);
        token.grantRole(token.MINTER_ROLE(), newController);
    }

    function createToken(
        address _poolAddress,
        Configuration.NOTE_TOKEN_TYPE _noteTokenType,
        uint8 _nDecimals
    ) external override whenNotPaused nonReentrant onlySecuritizationManager returns (address) {
        string memory name;
        string memory symbol;
        if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            name = 'Senior Obligation Token';
            symbol = 'SOT';
        } else {
            name = 'Junior Obligation Token';
            symbol = 'JOT';
        }
        NoteToken token = new NoteToken(name, symbol, _nDecimals, _poolAddress, uint8(_noteTokenType));

        tokens.push(token);
        isExistingTokens[address(token)] = true;

        return address(token);
    }

    function pauseUnpauseToken(address tokenAddress) external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTokens[tokenAddress], 'NoteTokenFactory: token does not exist');
        NoteToken token = NoteToken(tokenAddress);
        if (token.paused()) token.unpause();
        token.pause();
    }

    function pauseUnpauseAllTokens() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].paused()) tokens[i].unpause();
            else tokens[i].pause();
        }
    }
}
