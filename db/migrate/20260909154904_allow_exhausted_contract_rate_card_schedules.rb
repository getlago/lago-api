# frozen_string_literal: true

class AllowExhaustedContractRateCardSchedules < ActiveRecord::Migration[8.0]
  def change
    change_column_null :contract_rate_cards, :next_billing_at, true
  end
end
