# frozen_string_literal: true

class CreatePlanWallets < ActiveRecord::Migration[8.1]
  def change
    create_enum :plan_wallet_tax_application, %w[tax_on_consumption tax_on_purchase]

    create_table :plan_wallets, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :catalog_plan, type: :uuid, null: false, foreign_key: true, index: false

      t.string :code, null: false
      t.string :name
      t.string :invoice_display_name
      t.string :currency, null: false
      t.enum :tax_application, enum_type: :plan_wallet_tax_application, null: false, default: "tax_on_consumption"
      t.integer :priority, null: false, default: 50
      t.bigint :top_up_min_amount_cents
      t.bigint :top_up_max_amount_cents

      t.datetime :deleted_at

      t.timestamps

      t.index %i[catalog_plan_id code], unique: true, where: "deleted_at IS NULL"

      t.check_constraint "top_up_min_amount_cents <= top_up_max_amount_cents",
        name: "plan_wallets_top_up_min_not_above_max"
    end
  end
end
