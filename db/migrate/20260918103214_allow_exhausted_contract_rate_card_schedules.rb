# frozen_string_literal: true

class AllowExhaustedContractRateCardSchedules < ActiveRecord::Migration[8.0]
  # A schedule that has run out has no next billing instant, and leaving the last one in
  # place makes the column claim a billing that will never happen. NULL says it plainly,
  # and keeps the card out of the producer's selection without a second predicate.
  def change
    change_column_null :contract_rate_cards, :next_billing_at, true
  end
end
