# frozen_string_literal: true

class AddCoverageToBillingOperations < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_operations, :coverage_started_at, :datetime, if_not_exists: true
    add_column :billing_operations, :coverage_ended_at, :datetime, if_not_exists: true

    # There are no existing billing operations in production to backfill.
    safety_assured do
      change_column_null :billing_operations, :coverage_started_at, false
      change_column_null :billing_operations, :coverage_ended_at, false
    end
  end
end
