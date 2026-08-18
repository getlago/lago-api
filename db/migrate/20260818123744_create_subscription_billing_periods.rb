# frozen_string_literal: true

class CreateSubscriptionBillingPeriods < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_billing_periods, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, null: false, foreign_key: true, index: false
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true

      # The aggregation unit. Legacy plans write ("Subscription", subscription_id): all of a
      # subscription's charges share one charges period. The product catalog will write
      # ("SubscriptionRateCard", subscription_rate_card_id), since each rate card bills on its own
      # cycle. NOT NULL so the unique index needs no NULLS NOT DISTINCT and adding the second scope
      # needs no migration on a table that is by then a CDC source.
      t.string :scope_type, null: false
      t.uuid :scope_id, null: false

      t.datetime :period_from, null: false
      t.datetime :period_to, null: false

      t.timestamps

      # The rows are written with upsert_all, which skips model validations, so the ordering the
      # model validates is enforced here too.
      t.check_constraint "period_to > period_from", name: "subscription_billing_periods_period_order"

      t.index %i[scope_id period_from], unique: true
      # Drives the rollover sweep, which is what keeps it an index scan rather than a walk over
      # every active subscription.
      t.index :period_to
    end
  end
end
