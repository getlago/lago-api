# frozen_string_literal: true

class AddPeriodOverlapConstraintToBillingCycles < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      enable_extension "btree_gist"

      execute <<~SQL
        ALTER TABLE billing_cycles
        ADD CONSTRAINT billing_cycles_no_overlapping_periods
        EXCLUDE USING gist (
          organization_id WITH =,
          subscription_id WITH =,
          customer_id WITH =,
          subscription_rate_card_id WITH =,
          tsrange(period_from, period_to, '[]') WITH &&
        )
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        ALTER TABLE billing_cycles
        DROP CONSTRAINT IF EXISTS billing_cycles_no_overlapping_periods
      SQL
    end
  end
end
