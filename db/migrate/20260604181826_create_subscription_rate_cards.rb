# frozen_string_literal: true

class CreateSubscriptionRateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :subscription_rate_cards, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subscription, null: false, foreign_key: true, type: :uuid
      t.references :rate_card, null: false, foreign_key: true, type: :uuid

      t.date :billing_anchor_date, null: false
      t.timestamp :next_billing_at, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.decimal :units, precision: 30, scale: 10

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:subscription_id, :rate_card_id],
        unique: true,
        where: "deleted_at IS NULL AND ended_at IS NULL",
        name: "index_active_subscription_rate_cards_on_sub_and_card"
      t.index :next_billing_at,
        where: "deleted_at IS NULL AND ended_at IS NULL",
        name: "idx_spi_billable"

      t.check_constraint "ended_at IS NULL OR started_at <= ended_at",
        name: "subscription_rate_cards_started_before_ended"
    end
  end
end
