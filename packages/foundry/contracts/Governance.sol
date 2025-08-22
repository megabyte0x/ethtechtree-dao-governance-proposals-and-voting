// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Governance {
    error PROPOSAL_DOESNT_EXIST();
    error USER_DOESNT_HOLD_DRT_TOKEN();
    error PROPOSAL_QUEUE_FULL();
    error NO_ACTIVE_PROPOSAL();
    error ALREADY_VOTED();
    error WRONG_INPUT();
    error NOT_DRT_TOKEN();
    error USER_HAVENT_VOTED();
    error VOTING_PERIOD_NOT_OVER();
    error VOTING_PERIOD_OVER();

    event ProposalCreated(uint256 proposalId, string title, uint256 votingDeadline, address creator);
    event VoteCasted(uint256 proposalId, address voter, uint8 vote, uint256 weight);
    event VotesRemoved(address voter, uint8 vote, uint256 weight);

    struct VoteDetails {
        bool didVote;
        VOTE vote;
    }

    struct Proposal {
        string title;
        uint256 votingDeadline;
        address creator;
        mapping(address => VoteDetails) voters;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    struct ActiveProposal {
        uint256 activeProposalId;
        uint256 queuedProposalId;
    }

    enum VOTE {
        Against,
        For,
        Abstaining
    }

    IERC20 public immutable i_drtToken;
    uint256 public immutable i_timePeriod;

    ActiveProposal public s_activeProposal;
    uint256 public s_totalProposals;
    mapping(uint256 => Proposal) s_proposals;

    constructor(address drtTokenAddress, uint256 timePeriod) {
        i_drtToken = IERC20(drtTokenAddress);
        i_timePeriod = timePeriod;
    }

    modifier doesProposalExist(uint256 proposalId) {
        if (s_proposals[proposalId].creator == address(0)) {
            revert PROPOSAL_DOESNT_EXIST();
        }
        _;
    }

    modifier holdsDRTToken() {
        if (i_drtToken.balanceOf(msg.sender) == 0) {
            revert USER_DOESNT_HOLD_DRT_TOKEN();
        }
        _;
    }

    modifier checkIfQueueIsFull() {
        if (s_proposals[s_activeProposal.queuedProposalId].votingDeadline > block.timestamp) {
            revert PROPOSAL_QUEUE_FULL();
        }
        _;
    }

    function propose(string memory title) external checkIfQueueIsFull holdsDRTToken returns (uint256) {
        uint256 proposalId = s_totalProposals + 1;

        s_totalProposals += 1;

        if (s_activeProposal.activeProposalId == 0) {
            s_activeProposal.activeProposalId = proposalId;
            s_proposals[proposalId].votingDeadline = block.timestamp + i_timePeriod;
            s_proposals[proposalId].creator = msg.sender;
            s_proposals[proposalId].title = title;

            emit ProposalCreated(proposalId, title, block.timestamp + i_timePeriod, msg.sender);

            return proposalId;
        }

        Proposal storage activeProposal = s_proposals[s_activeProposal.activeProposalId];
        Proposal storage queuedProposal = s_proposals[s_activeProposal.queuedProposalId];

        if (activeProposal.votingDeadline > block.timestamp) {
            s_activeProposal.queuedProposalId = proposalId;
            s_proposals[proposalId].votingDeadline = activeProposal.votingDeadline + i_timePeriod;
        } else if (activeProposal.votingDeadline < block.timestamp && queuedProposal.votingDeadline > block.timestamp) {
            s_activeProposal.activeProposalId = s_activeProposal.queuedProposalId;
            s_activeProposal.queuedProposalId = proposalId;
            s_proposals[proposalId].votingDeadline = activeProposal.votingDeadline + i_timePeriod;
        } else if (activeProposal.votingDeadline < block.timestamp && queuedProposal.votingDeadline < block.timestamp) {
            s_activeProposal.activeProposalId = proposalId;
            s_activeProposal.queuedProposalId = 0;
            s_proposals[proposalId].votingDeadline = block.timestamp + i_timePeriod;
        }

        s_proposals[proposalId].creator = msg.sender;
        s_proposals[proposalId].title = title;

        emit ProposalCreated(proposalId, title, block.timestamp + i_timePeriod, msg.sender);

        return proposalId;
    }

    function getProposal(uint256 proposalId)
        external
        view
        doesProposalExist(proposalId)
        returns (string memory title, uint256 deadline, address creator)
    {
        Proposal storage proposal = s_proposals[proposalId];

        title = proposal.title;
        deadline = proposal.votingDeadline;
        creator = proposal.creator;
    }

    function vote(uint8 _vote) external holdsDRTToken {
        if (s_activeProposal.activeProposalId == 0) {
            revert NO_ACTIVE_PROPOSAL();
        }

        Proposal storage proposal = s_proposals[s_activeProposal.activeProposalId];

        Proposal storage queuedProposal = s_proposals[s_activeProposal.queuedProposalId];

        if (proposal.votingDeadline < block.timestamp) {
            if (queuedProposal.votingDeadline < block.timestamp) {
                revert VOTING_PERIOD_OVER();
            } else {
                s_activeProposal.activeProposalId = s_activeProposal.queuedProposalId;

                proposal = s_proposals[s_activeProposal.queuedProposalId];

                s_activeProposal.queuedProposalId = 0;
            }
        }

        if (proposal.voters[msg.sender].didVote) {
            revert ALREADY_VOTED();
        }

        if (_vote > uint8(type(VOTE).max)) {
            revert WRONG_INPUT();
        }

        proposal.voters[msg.sender].didVote = true;

        if (VOTE(_vote) == VOTE.Against) {
            proposal.voters[msg.sender].vote = VOTE.Against;
            proposal.votesAgainst += i_drtToken.balanceOf(msg.sender);
        } else if (VOTE(_vote) == VOTE.For) {
            proposal.voters[msg.sender].vote = VOTE.For;
            proposal.votesFor += i_drtToken.balanceOf(msg.sender);
        } else {
            proposal.voters[msg.sender].vote = VOTE.Abstaining;
        }

        emit VoteCasted(s_activeProposal.activeProposalId, msg.sender, _vote, i_drtToken.balanceOf(msg.sender));
    }

    function removeVotes(address from) external {
        if (msg.sender != address(i_drtToken)) {
            revert NOT_DRT_TOKEN();
        }

        Proposal storage proposal = s_proposals[s_activeProposal.activeProposalId];

        if (!proposal.voters[from].didVote) {
            revert USER_HAVENT_VOTED();
        }

        proposal.voters[from].didVote = false;

        if (proposal.voters[from].vote == VOTE.For) {
            proposal.votesFor -= i_drtToken.balanceOf(from);
        } else if (proposal.voters[from].vote == VOTE.Against) {
            proposal.votesAgainst -= i_drtToken.balanceOf(from);
        }

        emit VotesRemoved(from, uint8(proposal.voters[from].vote), i_drtToken.balanceOf(from));
    }

    function getResult(uint256 proposalId) external view returns (bool) {
        Proposal storage proposal = s_proposals[proposalId];
        if (proposal.votingDeadline > block.timestamp) {
            revert VOTING_PERIOD_NOT_OVER();
        }

        return proposal.votesFor > proposal.votesAgainst;
    }
}
