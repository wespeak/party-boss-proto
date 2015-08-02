require_relative 'base_object'
require_relative 'config'
require_relative 'dice_allocation'
require_relative 'dice_outcome'
require_relative 'tactics/played_tactic'

class LegislativeSession < BaseObject

  # define the data that goes in this object
  Members = [
    { name: "bills_A",       type: Bill,         is_array: true },
    { name: "bills_B",       type: Bill,         is_array: true },
    { name: "allocation_A",  type: DiceAllocation              },
    { name: "allocation_B",  type: DiceAllocation              },
    { name: "tactics",       type: PlayedTactic, is_array: true },
    { name: "outcomes_A",    type: DiceOutcome,  is_array: true },
    { name: "outcomes_B",    type: DiceOutcome,  is_array: true },
    { name: "bills_dealt_A", type: Bill,         is_array: true },
    { name: "bills_dealt_B", type: Bill,         is_array: true },
  ]

  def LegislativeSession.run_session(game_snapshot, boss_A, boss_B, dice_roller)
    Logger.header("Boss 'A' choosing bills").indent
    bills_A = boss_A.get_bills
    Logger.unindent
    Logger.header("Boss 'A' choosing dice allocation").indent
    allocation_A = boss_A.get_allocation(game_snapshot.board.num_leadership_dice('A'),
                                         bills_A)
    Logger.unindent
    Logger.header("Boss 'B' choosing bills").indent
    bills_B = boss_B.get_bills
    Logger.unindent
    Logger.header("Boss 'B' choosing dice allocation").indent
    allocation_B = boss_B.get_allocation(game_snapshot.board.num_leadership_dice('B'),
                                         bills_B)
    Logger.unindent
    legislative_session = LegislativeSession.new(bills_A,
                                                 bills_B,
                                                 allocation_A,
                                                 allocation_B,
                                                 [], [], [], [], [])

    last_last_was_pass = false
    last_was_pass = false
    party = 'A'
    while !last_was_pass || !last_last_was_pass
      Logger.header(LegislativeSessionRenderer.get.render_bills_on_floor legislative_session)
      Logger.header("Boss #{party} choosing a tactic").indent
      boss = party == 'A' ? boss_A : boss_B
      arr = boss.get_tactic(legislative_session)
      tactic = arr[0]
      if tactic == Tactic::Pass
        if last_was_pass
          last_last_was_pass = true
        end
        last_was_pass = true
      else
        last_was_pass = false
        index = arr[1]
        party_played_on = arr[2]
        if !tactic.can_play(party, party_played_on, bills_A[index], bills_B[index], game_snapshot.board)
          Logger.error "This tactic cannot be played like this"
          # make them choose again
          party = (party == 'A' ? 'B' : 'A')
        else
          game_snapshot.send("hand_#{party}").tactics.delete_if do |hand_tactic|
            hand_tactic.equals?(tactic)
          end
          legislative_session.tactics.push(PlayedTactic.new(party,
                                                            party_played_on,
                                                            bills_A[index],
                                                            bills_B[index],
                                                            tactic))
        end
      end
      party = (party == 'A' ? 'B' : 'A')
      Logger.unindent
    end
    
    Logger.header(LegislativeSessionRenderer.get.render_bills_on_floor legislative_session)

    legislative_session.outcomes_A.concat(dice_roller.get_outcomes(allocation_A))
    legislative_session.outcomes_B.concat(dice_roller.get_outcomes(allocation_B))
    
    game_snapshot.apply_legislative_session(legislative_session, false)
  end

  def passes?(index, party)
    bill = send("bills_#{party}")[index]
    send("outcomes_#{party}")[index].sum >= bill.vps ? bill : nil
  end

  def vps(index, party, board)
    bill = send("bills_#{party}")[index]
    if passes?(index, party)
      bill.vps + (bill.sector == board.state_of_the_union.priorities[0] ? 1 : 0)
    else
      0
    end
  end
end