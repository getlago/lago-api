# frozen_string_literal: true

class CreateDailyUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :daily_usages, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, null: false, foreign_key: true, index: true
      t.string :external_subscription_id, null: false
      t.datetime :from_datetime, null: false
      t.datetime :to_datetime, null: false
      t.jsonb :usage, null: false, default: '{}'
      t.timestamps

      t.index %i[organization_id external_subscription_id]
    end
  end
end
