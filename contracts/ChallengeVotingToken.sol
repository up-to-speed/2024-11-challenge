// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ChallengeVotingToken is ERC20, Ownable {

    constructor() ERC20("Challenge Voting Token", "CVT") Ownable(msg.sender) {}

    // Allow owner to mint additional tokens if needed
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Allow users to burn their own tokens
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // Snapshot functionality could be added here if we want to track voting power at specific blocks
} 