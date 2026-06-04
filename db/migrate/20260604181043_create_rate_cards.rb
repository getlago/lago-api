# frozen_string_literal: true

class CreateRateCards < ActiveRecord::Migration[8.0]
  def change
    create_enum :rate_card_billing_timing, %w[arrears advance]
    create_enum :rate_card_proration, %w[full none]
    create_enum :rate_card_regroup_paid_fees, %w[invoice]

    create_table :rate_cards, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product_item, null: false, foreign_key: true, type: :uuid
      t.references :product_item_filter, null: true, foreign_key: true, type: :uuid

      t.string :code, null: false
      t.string :name, null: false
      t.string :description

      t.string :currency, null: false

      t.enum :billing_timing, enum_type: :rate_card_billing_timing, null: false, default: "arrears"
      t.enum :proration, enum_type: :rate_card_proration, null: false, default: "full"
      t.boolean :display_on_invoice, null: false, default: true
      t.enum :regroup_paid_fees, enum_type: :rate_card_regroup_paid_fees
      t.string :applied_pricing_unit_code
      t.boolean :wallet_targetable

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:product_item_id, :product_item_filter_id, :code],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_rate_cards_on_item_filter_and_code"
      t.index [:product_item_id, :code],
        unique: true,
        where: "product_item_filter_id IS NULL AND deleted_at IS NULL",
        name: "index_filterless_rate_cards_on_product_item_id_and_code"
    end
  end
end
