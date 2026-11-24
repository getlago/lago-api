# frozen_string_literal: true

class AddTimestampedUnitsBillingInputs < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_rate_cards_terms, :effective_at, :datetime, if_not_exists: true
    change_column_null :contract_rate_cards_terms, :effective_date, true
    add_column :billing_operations, :pricing_segments, :jsonb, if_not_exists: true
  end
end
