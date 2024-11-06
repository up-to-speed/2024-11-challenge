// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ProposalVoting is Ownable {
    enum ProposalState { Initialized, Open, Executed, Closed }

    mapping(bytes32 => bool) public winners;

    struct Proposal {
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 endTime;
        uint256 quorum;
        bytes32 winnerHash;
    }

    struct VoterInfo {
        uint256 voterCount;
        uint256 votersRemaining; 
        mapping(address => bool) hasVoted;
        mapping(address => bool) canVote;
        mapping(address => uint256) votingPowerUsed;
        mapping(address => uint256) votingPowerSnapshot;
    }

    mapping(string => ProposalState) public proposalStates;
    mapping(string => Proposal) public proposals;
    mapping(string => VoterInfo) public voterInfos;

    IERC20 public votingToken;

    address public votingController;
    bool public votingPaused;

    address public pendingOwner;

    event VotingControllerChanged(address indexed previousController, address indexed newController);
    event VotingPaused(address indexed controller);
    event VotingResumed(address indexed controller);

    event WinnerAdded(bytes32 indexed winnerHash);

    event ProposalClosed(string indexed proposalName);
    event ProposalRenamed(string indexed oldName, string indexed newName);

    modifier onlyVotingController() {
        require(msg.sender == votingController, "Only voting controller can call");
        _;
    }

    modifier whenVotingActive() {
        require(!votingPaused, "Voting is currently paused");
        _;
    }

    constructor(address _votingToken) Ownable(msg.sender) {
        votingToken = IERC20(_votingToken);
        votingController = msg.sender;
    }

    event ProposalCreated(string indexed proposalName, string description);
    event Voted(string indexed proposalName, address indexed voter, bool vote);
    event ProposalExecuted(string indexed proposalName);
    event ProposalResult(string indexed proposalName, bool passed);
    event ProposalDeleted(string indexed proposalName, string indexed description, bytes32 indexed winnerHash);


    modifier proposalNotAlreadyExisting(string memory _proposalName) {
        require(voterInfos[_proposalName].voterCount == 0);
        _;
    }

    function createProposal(
        string memory _proposalName,
        string memory _description,
        uint256 _votingPeriodInSeconds,
        address[] memory _allowedVoters,
        bytes32 _winnerHash
    ) external whenVotingActive {
        proposals[_proposalName] = Proposal("", 0, 0, 0, 0, 0);
        Proposal storage proposal = proposals[_proposalName];
        VoterInfo storage voterInfo = voterInfos[_proposalName];
        
        require(!winners[_winnerHash], "Winner hash already exists");
        
        proposal.description = _description;
        proposal.endTime = block.timestamp + _votingPeriodInSeconds;
        proposal.winnerHash = _winnerHash;

        require(_allowedVoters.length < 10, "Too many allowed voters");

        uint256 totalVotingPower = 0;
        
        bool ownerIncluded = false;
        for (uint i = 0; i < _allowedVoters.length; i++) {
            address voter = _allowedVoters[i];
            if (!voterInfo.canVote[voter]) {
                voterInfo.canVote[voter] = true;
                voterInfo.voterCount++;
                voterInfo.votersRemaining++;
                voterInfo.votingPowerSnapshot[voter] = getVotingPower(voter);
                totalVotingPower += voterInfo.votingPowerSnapshot[voter];
            }
            if (voter == owner()) {
                ownerIncluded = true;
            }
        }
        
        if (!ownerIncluded) {
            voterInfo.canVote[owner()] = true;
            voterInfo.voterCount++;
            voterInfo.votersRemaining++;
            voterInfo.votingPowerSnapshot[owner()] = getVotingPower(owner());
            totalVotingPower += voterInfo.votingPowerSnapshot[owner()];
            
        }
        
        proposal.quorum = (totalVotingPower * 51) / 100;

        proposalStates[_proposalName] = ProposalState.Initialized;
        
        emit ProposalCreated(_proposalName, _description);
    }

    function openVoting(string memory _proposalName) whenVotingActive external {
        require(proposalStates[_proposalName] == ProposalState.Initialized, "Proposal not initialized");
        proposalStates[_proposalName] = ProposalState.Open;
    }

    function getVotingPower(address voter) public view returns (uint256) {
        uint256 tokenBalance = votingToken.balanceOf(voter);
        uint256 basePower = (tokenBalance / 1e18) + 1;
        
        if (voter == owner()) {
            return 20;
        }
        
        return basePower;
    }

    function vote(string memory _proposalName, bool _support, uint256 votingPower) external whenVotingActive {
        require(proposalStates[_proposalName] == ProposalState.Open, "Proposal not open");

        VoterInfo storage voterInfo = voterInfos[_proposalName];

        require(block.timestamp <= proposals[_proposalName].endTime, "Voting period has ended");
        require(!voterInfo.hasVoted[msg.sender], "Already voted");
        require(voterInfo.canVote[msg.sender], "Not allowed to vote on this proposal");
        
        uint256 maxPower = voterInfo.votingPowerSnapshot[msg.sender];
        require(votingPower <= maxPower, "Exceeds available voting power");

        voterInfo.hasVoted[msg.sender] = true;
        voterInfo.votingPowerUsed[msg.sender] = votingPower;
        voterInfo.votersRemaining--;

        if (_support) {
            proposals[_proposalName].yesVotes += votingPower;
        } else {
            proposals[_proposalName].noVotes += votingPower;
        }

        emit Voted(_proposalName, msg.sender, _support);
    }

    function executeProposal(string memory _proposalName) external {
        Proposal storage proposal = proposals[_proposalName];
        
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(proposalStates[_proposalName] == ProposalState.Open, "Proposal not open");
        
        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;
        require(totalVotes >= proposal.quorum, "Quorum not reached");

        bool proposalPassed = proposal.yesVotes > proposal.noVotes;
        
        if (proposalPassed) {
            proposalStates[_proposalName] = ProposalState.Executed;
            winners[proposal.winnerHash] = true;
            emit WinnerAdded(proposal.winnerHash);
        } else {
            proposalStates[_proposalName] = ProposalState.Closed;
        }
        
        emit ProposalExecuted(_proposalName);
        emit ProposalResult(_proposalName, proposalPassed);
    }
    function getProposal(string memory _proposalName) external view returns (
        string memory description,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 endTime,
        ProposalState state,
        uint256 quorum,
        bytes32 winnerHash,
        bool isVotingPaused
    ) {
        Proposal storage proposal = proposals[_proposalName];

        return (
            proposal.description,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.endTime,
            proposalStates[_proposalName],
            proposal.quorum,
            proposal.winnerHash,
            votingPaused
        );
    }

    function getProposalVoterInfo(string memory _proposalName, address voter) external view returns (
        uint256 voterCount,
        uint256 voterPower,
        uint256 powerUsed,
        uint256 votersRemaining
    ) {
        VoterInfo storage voterInfo = voterInfos[_proposalName];

        return (
            voterInfo.voterCount,
            voterInfo.votingPowerSnapshot[voter],
            voterInfo.votingPowerUsed[voter],
            voterInfo.votersRemaining
        );
    }

    function hasVoted(string memory _proposalName, address _voter) external view returns (bool) {
        return voterInfos[_proposalName].hasVoted[_voter];
    }

    function getVotingPowerUsed(string memory _proposalName, address voter) external view returns (uint256) {
        return voterInfos[_proposalName].votingPowerUsed[voter];
    }

    function transferOwnershipWithToken(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        require(votingToken.balanceOf(newOwner) > 0, "New owner must hold voting tokens");
        
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Only pending owner can accept");
        require(votingToken.balanceOf(msg.sender) > 0, "Must hold voting tokens to accept ownership");
        
        address oldOwner = owner();
        _transferOwnership(msg.sender);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function cancelOwnershipTransfer() external onlyOwner {
        require(pendingOwner != address(0), "No pending ownership transfer");
        address oldPendingOwner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferCanceled(oldPendingOwner);
    }

    function setVotingController(address newController) external onlyOwner {
        require(newController != address(0), "New controller is zero address");
        address oldController = votingController;
        votingController = newController;
        emit VotingControllerChanged(oldController, newController);
    }

    function pauseVoting() external onlyVotingController {
        require(!votingPaused, "Voting already paused");
        votingPaused = true;
        emit VotingPaused(msg.sender);
    }

    function resumeVoting() external onlyVotingController {
        require(votingPaused, "Voting not paused");
        votingPaused = false;
        emit VotingResumed(msg.sender);
    }

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferCanceled(address indexed previousPendingOwner);

    function transferOwnership(address) public pure override {
        revert("Use transferOwnershipWithToken");
    }

    function renounceOwnership() public pure override {
        revert("Ownership cannot be renounced");
    }

    function isWinner(bytes32 hash) external view returns (bool) {
        return winners[hash];
    }

    function getSnapshotPower(string memory _proposalName, address voter) external view returns (uint256) {
        return voterInfos[_proposalName].votingPowerSnapshot[voter];
    }

    function getProposalState(string memory _proposalName) external view returns (ProposalState) {
        return proposalStates[_proposalName];
    }

    function closeProposal(string memory _proposalName) external {
        Proposal memory proposal = proposals[_proposalName];
        require(proposalStates[_proposalName] == ProposalState.Open, "Proposal not open");
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        
        proposalStates[_proposalName] = ProposalState.Closed;
        emit ProposalClosed(_proposalName);
    }

    function deleteProposal(string memory _proposalName) external {
        require(proposalStates[_proposalName] == ProposalState.Closed, "Proposal not closed");
        Proposal memory proposal = proposals[_proposalName];

        emit ProposalDeleted(_proposalName, proposal.description, proposal.winnerHash);

        delete proposalStates[_proposalName];
        delete proposal;
        delete voterInfos[_proposalName];
    }

    function renameProposal(string memory oldName, string memory newName) external {
        require(bytes(newName).length > 0, "Empty name not allowed");
        require(bytes(proposals[newName].description).length == 0, "New name already in use");
        require(proposalStates[oldName] == ProposalState.Initialized, "Can only rename pre-open proposals");
        
        Proposal memory oldProposal = proposals[oldName];
        proposals[newName] = oldProposal;
        delete proposals[oldName];

        emit ProposalRenamed(oldName, newName);
    }
}