# frozen_string_literal: true

class CreateSubscriptionBillingPeriods < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_billing_periods, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, null: false, foreign_key: true, index: false
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true
      t.string :scope_type
      t.uuid :scope_id
      t.datetime :period_from, null: false
      t.datetime :period_to, null: false

      t.timestamps

      t.index %i[subscription_id period_from], unique: true
    end
  end
end
