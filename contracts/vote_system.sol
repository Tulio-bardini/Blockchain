// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract PartiesAndVotersControl is AccessControl {
    // Roles
    bytes32 public constant ROOT_ADMIN_ROLE = keccak256("ROOT_ADMIN_ROLE");
    bytes32 public constant PARTY_ROLE = keccak256("PARTY_ROLE");

    // Mapping of request states: party => voter => state
    enum RequestState { NeverRequested, Cleared, Pending }
    mapping(address => mapping(address => RequestState)) public requestStatus;

    // Voters per Party
    mapping(address => mapping(address => bool)) public isVoterOfParty;

    // Parties per Voter (optional, if you want to keep track of which parties a voter is in)
    mapping(address => address[]) public partiesOfVoter;

    // Array to store all voters that requested to participate in a party
    mapping(address => address[]) public allRequestedVoters;

    constructor() {
        _grantRole(ROOT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(PARTY_ROLE, ROOT_ADMIN_ROLE);
    }

    /// Voter requests access to a specific Party
    function requestVoter(address party) external {
        require(hasRole(PARTY_ROLE, party), "Destination is not a Party");
        require(requestStatus[party][msg.sender] != RequestState.Pending, "Request already sent");

        if (requestStatus[party][msg.sender] == RequestState.NeverRequested) {
            requestStatus[party][msg.sender] = RequestState.Pending;
            allRequestedVoters[party].push(msg.sender);         
        } else {
            requestStatus[party][msg.sender] = RequestState.Pending;
        }
    }

    /// Party accepts the Voter
    function acceptVoter(address voter) external {
        require(hasRole(PARTY_ROLE, msg.sender), "Only Party can accept");
        require(requestStatus[msg.sender][voter] == RequestState.Pending, "No pending request");

        // Register association
        isVoterOfParty[msg.sender][voter] = true;
        partiesOfVoter[voter].push(msg.sender);

        // Clear the request (set to Cleared)
        requestStatus[msg.sender][voter] = RequestState.Cleared;
    }

    /// Party rejects the Voter
    function rejectVoter(address voter) external {
        require(hasRole(PARTY_ROLE, msg.sender), "Only Party can reject");
        require(requestStatus[msg.sender][voter] == RequestState.Pending, "No pending request");

        // Clear the request (set to Cleared)
        requestStatus[msg.sender][voter] = RequestState.Cleared;
    }

    /// Party removes a Voter
    function removeVoter(address voter) external {
        require(hasRole(PARTY_ROLE, msg.sender), "Only Party can remove");

        // Remove from Party's voter mapping
        isVoterOfParty[msg.sender][voter] = false;

        // Remove Party from Voter's list
        _removeFromArray(partiesOfVoter[voter], msg.sender);
    }

    // Internal function to remove an address from an array
    function _removeFromArray(address[] storage arr, address target) internal {
        uint len = arr.length;
        for (uint i = 0; i < len; i++) {
            if (arr[i] == target) {
                arr[i] = arr[len - 1];
                arr.pop();
                break;
            }
        }
    }

    function getPartiesFromVoterPaginated(
        address voter,
        uint256 start,
        uint256 limit
    ) external view returns (address[] memory) {
        address[] storage fullList = partiesOfVoter[voter];
        uint256 end = start + limit;
        if (end > fullList.length) {
            end = fullList.length;
        }

        address[] memory page = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            page[i - start] = fullList[i];
        }

        return page;
    }

    /// Read all requested voters for a party (paginated)
    function getAllRequestedVotersPaginated(
        address party,
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory) {
        address[] storage fullList = allRequestedVoters[party];
        uint256 end = offset + limit;
        if (end > fullList.length) {
            end = fullList.length;
        }

        address[] memory page = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = fullList[i];
        }

        return page;
    }

    struct Voting {
        string description;
        uint256 deadline;
        mapping(address => bool) hasVoted;
        mapping(string => uint256) votes; // option => total votes
        string[] options;
    }

    mapping(uint256 => Voting) public globalVotings;
    mapping(address => mapping(uint256 => Voting)) public votingsByParty;

    uint256 public globalVotingCounter;
    mapping(address => uint256) public votingCounterByParty;

    /// Starts a global voting (ROOT_ADMIN)
    function startGlobalVoting(string memory description, string[] memory options, uint256 durationSeconds) external onlyRole(ROOT_ADMIN_ROLE) {
        Voting storage v = globalVotings[globalVotingCounter];
        v.description = description;
        v.deadline = block.timestamp + durationSeconds;
        v.options = options;
        globalVotingCounter++;
    }

    /// Any wallet (except Parties) can vote
    function voteGlobal(uint256 id, string memory option) external {
        Voting storage v = globalVotings[id];
        require(block.timestamp <= v.deadline, "Voting closed");
        require(!v.hasVoted[msg.sender], "Already voted");
        require(!hasRole(PARTY_ROLE, msg.sender), "Parties cannot vote");

        v.votes[option]++;
        v.hasVoted[msg.sender] = true;
    }

    /// Starts a local voting (Party)
    function startLocalVoting(string memory description, string[] memory options, uint256 durationSeconds) external onlyRole(PARTY_ROLE) {
        Voting storage v = votingsByParty[msg.sender][votingCounterByParty[msg.sender]];
        v.description = description;
        v.deadline = block.timestamp + durationSeconds;
        v.options = options;
        votingCounterByParty[msg.sender]++;
    }

    /// Voter votes in local voting of their Party
    function voteLocal(address party, uint256 id, string memory option) external {
        require(isVoterOfParty[party][msg.sender], "Not a member of this Party");
        Voting storage v = votingsByParty[party][id];
        require(block.timestamp <= v.deadline, "Voting closed");
        require(!v.hasVoted[msg.sender], "Already voted");

        v.votes[option]++;
        v.hasVoted[msg.sender] = true;
    }

    /// Returns total votes for an option in a global voting
    function totalVotesGlobal(uint256 id, string memory option) external view returns (uint256) {
        return globalVotings[id].votes[option];
    }

    /// Returns total votes for an option in a local voting
    function totalVotesLocal(address party, uint256 id, string memory option) external view returns (uint256) {
        return votingsByParty[party][id].votes[option];
    }

    /// Checks if an address is a Voter of a Party
    function isVoterOfPartyFunc(address voter, address party) public view returns (bool) {
        return isVoterOfParty[party][voter];
    }

    /// Returns all global votings (paginated)
    function getGlobalVotings(uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        uint256 end = offset + limit;
        if (end > globalVotingCounter) {
            end = globalVotingCounter;
        }
        uint256[] memory result = new uint256[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = i;
        }
        return result;
    }

    /// Returns all local votings for a specific party (paginated, open or closed)
    function getLocalVotings(address party, uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        uint256 numVotings = votingCounterByParty[party];
        uint256 end = offset + limit;
        if (end > numVotings) {
            end = numVotings;
        }
        uint256[] memory votingIds = new uint256[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            votingIds[i - offset] = i;
        }
        return votingIds;
    }

    /// Public getter for global voting details
    function getGlobalVotingDetails(uint256 id) external view returns (
        string memory description,
        uint256 deadline,
        string[] memory options
    ) {
        Voting storage v = globalVotings[id];
        return (v.description, v.deadline, v.options);
    }

    /// Public getter for local voting details
    function getLocalVotingDetails(address party, uint256 id) external view returns (
        string memory description,
        uint256 deadline,
        string[] memory options
    ) {
        Voting storage v = votingsByParty[party][id];
        return (v.description, v.deadline, v.options);
    }
}
