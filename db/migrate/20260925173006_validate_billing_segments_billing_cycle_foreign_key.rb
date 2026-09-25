# frozen_string_literal: true

class ValidateBillingSegmentsBillingCycleForeignKey < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :billing_segments, column: :billing_cycle_id
  end
end
