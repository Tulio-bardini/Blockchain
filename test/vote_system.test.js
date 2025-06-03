const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PartiesAndVotersControl", function () {
  let contract, owner, party1, party2, voter1, voter2, voter3;

  beforeEach(async function () {
    [owner, party1, party2, voter1, voter2, voter3] = await ethers.getSigners();
    const Contract = await ethers.getContractFactory("PartiesAndVotersControl");
    contract = await Contract.deploy();

    // Grant PARTY_ROLE to party1 and party2
    await contract.connect(owner).grantRole(await contract.PARTY_ROLE(), party1.address);
    await contract.connect(owner).grantRole(await contract.PARTY_ROLE(), party2.address);
  });

  it("should allow a voter to request to join a party", async function () {
    await contract.connect(voter1).requestVoter(party1.address);
    const status = await contract.requestStatus(party1.address, voter1.address);
    expect(status).to.equal(2); // Pending
    const allRequested = await contract.getAllRequestedVotersPaginated(party1.address, 0, 10);
    expect(allRequested).to.include(voter1.address);
  });

  it("should allow a party to accept a voter", async function () {
    await contract.connect(voter1).requestVoter(party1.address);
    await contract.connect(party1).acceptVoter(voter1.address);
    expect(await contract.isVoterOfParty(party1.address, voter1.address)).to.be.true;
    const parties = await contract.getPartiesFromVoterPaginated(voter1.address, 0, 10);
    expect(parties).to.include(party1.address);
    const status = await contract.requestStatus(party1.address, voter1.address);
    expect(status).to.equal(1); // Cleared
  });

  it("should allow a party to reject a voter", async function () {
    await contract.connect(voter2).requestVoter(party2.address);
    await contract.connect(party2).rejectVoter(voter2.address);
    expect(await contract.isVoterOfParty(party2.address, voter2.address)).to.be.false;
    const status = await contract.requestStatus(party2.address, voter2.address);
    expect(status).to.equal(1); // Cleared
  });

  it("should allow a party to remove a voter", async function () {
    await contract.connect(voter1).requestVoter(party1.address);
    await contract.connect(party1).acceptVoter(voter1.address);
    await contract.connect(party1).removeVoter(voter1.address);
    expect(await contract.isVoterOfParty(party1.address, voter1.address)).to.be.false;
  });

  it("should allow global voting and voting by eligible voters", async function () {
    await contract.connect(owner).startGlobalVoting("Test Global", ["yes", "no"], 1000);
    const votings = await contract.getGlobalVotings(0, 10);
    expect(votings.length).to.equal(1);

    // Check description and options of the election using the new getter
    const votingId = votings[0];
    const [description, deadline, options] = await contract.getGlobalVotingDetails(votingId);
    expect(description).to.equal("Test Global");
    expect(options[0]).to.equal("yes");
    expect(options[1]).to.equal("no");

    await contract.connect(voter1).voteGlobal(votingId, "yes");
    const votes = await contract.totalVotesGlobal(votingId, "yes");
    expect(votes).to.equal(1);
  });

  it("should not allow voting in a global election that has already finished", async function () {
    await contract.connect(owner).startGlobalVoting("Finished Vote", ["yes", "no"], 1); // 1 second duration
    const votings = await contract.getGlobalVotings(0, 10);
    expect(votings.length).to.be.greaterThan(0);
    const votingId = votings[0];

    // Wait for the voting to finish
    await new Promise(resolve => setTimeout(resolve, 1500)); // Wait 1.5 seconds

    // Try to vote after the deadline
    await expect(
      contract.connect(voter1).voteGlobal(votingId, "yes")
    ).to.be.revertedWith("Voting closed");
  });

  it("should allow local voting and voting by party members", async function () {
    await contract.connect(voter1).requestVoter(party1.address);
    await contract.connect(party1).acceptVoter(voter1.address);
    await contract.connect(party1).startLocalVoting("Local Vote", ["a", "b"], 1000);

    const localVotings = await contract.getLocalVotings(party1.address, 0, 10);
    expect(localVotings.length).to.equal(1);

    const localVotingId = localVotings[0];
    await contract.connect(voter1).voteLocal(party1.address, localVotingId, "a");
    const votes = await contract.totalVotesLocal(party1.address, localVotingId, "a");
    expect(votes).to.equal(1);
  });

  it("should allow reading voting details", async function () {
    await contract.connect(voter1).requestVoter(party1.address);
    await contract.connect(party1).acceptVoter(voter1.address);
    await contract.connect(party1).startLocalVoting("Local Vote", ["a", "b"], 1000);

    const localVotings = await contract.getLocalVotings(party1.address, 0, 10);
    expect(localVotings.length).to.equal(1);

    const localVotingId = localVotings[0];
    const [description, deadline, options] = await contract.getLocalVotingDetails(party1.address, localVotingId);
    expect(description).to.equal("Local Vote");
    expect(options[0]).to.equal("a");
    expect(options[1]).to.equal("b");
  });

  it("should not allow non-members to vote in local voting", async function () {
    await contract.connect(party1).startLocalVoting("Local Vote", ["a", "b"], 1000);
    await expect(
      contract.connect(voter2).voteLocal(party1.address, 0, "a")
    ).to.be.revertedWith("Not a member of this Party");
  });
});