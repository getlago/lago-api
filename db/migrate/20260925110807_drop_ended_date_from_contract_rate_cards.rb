# frozen_string_literal: true

class DropEndedDateFromContractRateCards < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      remove_column :contract_rate_cards, :ended_date
    end
  end

  def down
    add_column :contract_rate_cards, :ended_date, :date
    add_check_constraint :contract_rate_cards,
      "ended_date IS NULL OR effective_date <= ended_date",
      name: "contract_rate_cards_effective_before_ended"
  end
end
