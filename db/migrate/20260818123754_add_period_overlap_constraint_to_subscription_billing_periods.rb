# frozen_string_literal: true

# Deferred to commit: refreshing a subscription's periods deletes the rows it no longer wants and
# upserts the ones it does, and a boundary that moved leaves those two sets transiently overlapping.
# Only the state at commit has to be non-overlapping.
class AddPeriodOverlapConstraintToSubscriptionBillingPeriods < ActiveRecord::Migration[8.0]
  def up
    enable_extension "btree_gist"

    safety_assured do
      execute <<~SQL
        ALTER TABLE subscription_billing_periods
        ADD CONSTRAINT subscription_billing_periods_no_overlapping_periods
        EXCLUDE USING gist (
          scope_id WITH =,
          tsrange(period_from, period_to, '[]') WITH &&
        )
        DEFERRABLE INITIALLY DEFERRED
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        ALTER TABLE subscription_billing_periods
        DROP CONSTRAINT IF EXISTS subscription_billing_periods_no_overlapping_periods
      SQL
    end
  end
end
