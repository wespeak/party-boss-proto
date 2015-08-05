require_relative 'base_object'
require_relative 'config'
require_relative 'board'
require_relative 'hand'

class GameState < BaseObject

  # define the data that goes in this object
  Members = [
    { name: "board",  type: Board },
    { name: "hand_A", type: Hand  },
    { name: "hand_B", type: Hand  },
    { name: "politician_deck",         type: Politician,      is_array: true, unordered: true },
    { name: "bill_deck",               type: Bill,            is_array: true, unordered: true },
    { name: "state_of_the_union_deck", type: StateOfTheUnion, is_array: true, unordered: true },
    { name: "tactic_deck",             type: Tactic,          is_array: true, unordered: true },
  ]

  # utility method for creating a new game
  def GameState.new_game
    # create the decks of politicians
    politician_deck = Politician.from_array_file('src/data/politicians.json').shuffle
    bill_deck = Bill.from_array_file('src/data/bills.json').shuffle
    state_of_the_union_deck = StateOfTheUnion.from_array_file('src/data/state_of_the_unions.json').shuffle
    tactic_deck = Tactic.from_array_file('src/data/tactics.json')
    # set the initial office holders from the politician_deck
    office_holders = []
    Config.get.seats_num.times do
      office_holders.push OfficeHolder.new(office_holders.count % 2 == 0 ? 'A' : 'B', politician_deck.pop)
    end
    # create the board
    board = Board.new(state_of_the_union_deck.pop, office_holders, ['A', 'B'].shuffle[0], [], [], 0, 0, 0, 0)
    # create the snapshot
    game_state = GameState.new(board,
                               Hand.new([], [], []),
                               Hand.new([], [], []),
                               politician_deck,
                               bill_deck,
                               state_of_the_union_deck,
                               tactic_deck)
    # deal the cards
    ['A', 'B'].each do |party|
      game_state.send("hand_#{party}").politicians.concat(game_state.deal_politicians party)
      game_state.send("hand_#{party}").bills.concat(game_state.deal_bills party)
      game_state.send("hand_#{party}").tactics.concat(game_state.deal_tactics party, Config.get.tactics_num_initial)
    end
    game_state
  end

  def apply_election(election, is_replay)
    # deal tactics before messing with the board
    ['A', 'B'].each do |party|
      if !is_replay
        # deal the cards
        num_unused = board.num_fundraising_dice(party, election.send("candidates_#{party}")) -
                     election.send("allocation_#{party}").sum
        election.send("tactics_dealt_#{party}")
          .concat(deal_tactics(party, Config.get.tactics_num_per_campaign_die * num_unused))
      else
        # this is a replay, so take the dealt cards out of the deck
        election.send("tactics_dealt_#{party}").each do |tactic|
          delete_from(tactic_deck, tactic)
        end
      end
      # put the cards in the hand
      send("hand_#{party}").tactics.concat(
        election.send("tactics_dealt_#{party}"))
    end

    # remove candidates from hands
    ['A', 'B'].each do |party|
      election.send("candidates_#{party}").each do |candidate|
        delete_from(send("hand_#{party}").politicians, candidate)
      end
    end

    # put the winners in office
    Config.get.seats_num.times do |index|
      result = election.get_result(index, board)
      board.office_holders[index] =
        OfficeHolder.new(result[:winning_party], result[:winner])
    end

    # handle the dealt politician cards
    ['A', 'B'].each do |party|
      if !is_replay
        # deal the cards
        election.send("politicians_dealt_#{party}").concat(deal_politicians party)
      else
        # this is a replay, so take the dealt cards out of the deck
        election.send("politicians_dealt_#{party}").each do |politician|
          delete_from(politician_deck, politician)
        end
      end
      # put the cards in the hand
      send("hand_#{party}").politicians.concat(
        election.send("politicians_dealt_#{party}"))
    end

    # put the losers back in the deck
    Config.get.seats_num.times do |index|
      result = election.get_result(index, board)
      politician_deck.push(result[:loser])
    end

    # zero out the extra fundraising dice
    board.fundraising_dice_A = 0
    board.fundraising_dice_B = 0

    election
  end

  def apply_legislative_session(legislative_session, is_replay)
    ['A', 'B'].each do |party|
      # remove bills from hands
      legislative_session.get_bills_on_floor(party).each do |bill|
        delete_from(send("hand_#{party}").bills, bill)
      end

      # sign winners into law
      Config.get.bills_num_on_floor.times do |index|
        bill = legislative_session.passes?(index, party)
        if bill
          board.send("passed_bills_#{party}").push(bill)
          board.increment_vps(party, legislative_session.vps(index, party, board))
        end
      end
    end

    # handle the dealt bill cards
    ['A', 'B'].each do |party|
      if !is_replay
        # deal the cards
        legislative_session.send("bills_dealt_#{party}").concat(deal_bills party)
      else
        # this is a replay, so take the dealt cards out of the deck
        legislative_session.send("bills_dealt_#{party}").each do |bill|
          delete_from(bill_deck, bill)
        end
      end
      # put the cards in the hand
      send("hand_#{party}").bills.concat(
        legislative_session.send("bills_dealt_#{party}"))      
    end

    # put the losers back in the deck
    ['A', 'B'].each do |party|
      Config.get.bills_num_on_floor.times do |index|
        if !legislative_session.passes?(index, party)
          bill_deck.push(legislative_session.get_bill_on_floor(index, party))
        end
      end
    end

    # handle the tactics
    legislative_session.played_tactics.each do |played_tactic|
      # remove from the hand if is a replay
      if is_replay
        hand = send("hand_#{played_tactic.party_played_by}")
        delete_from(hand.tactics, played_tactic.tactic)
      end
      # put played tactics back in the deck
      tactic_deck.push(played_tactic.tactic)
    end

    legislative_session
  end

  def delete_from(array, elem)
    array.delete_if do |array_elem|
      array_elem.equals?(elem)
    end
  end

  def deal_politicians(party)
    politician_deck.shuffle!
    num_to_deal = Config.get.politicians_num_in_party - send("hand_#{party}").politicians.count - board.num_encumbents(party)
    [num_to_deal, politician_deck.count].min.times.map do
      politician_deck.pop
    end
  end

  def deal_bills(party)
    bill_deck.shuffle!
    num_to_deal = Config.get.bills_num_in_committee - send("hand_#{party}").bills.count
    [num_to_deal, bill_deck.count].min.times.map do
      bill_deck.pop
    end
  end

  def deal_tactics(party, num_to_deal)
    tactic_deck.shuffle!
    [num_to_deal, tactic_deck.count].min.times.map do
      tactic_deck.pop
    end
  end

  def end_cycle(cycle, is_replay)
    old_state_of_the_union = board.state_of_the_union
    if !is_replay
      cycle.next_state_of_the_union = state_of_the_union_deck.shuffle!.pop
    else
      delete_from(state_of_the_union_deck, cycle.next_state_of_the_union)
    end
    board.state_of_the_union = cycle.next_state_of_the_union
    state_of_the_union_deck.push old_state_of_the_union
    board.tactics_lead_party = board.tactics_lead_party == 'A' ? 'B' : 'A'
  end

end
