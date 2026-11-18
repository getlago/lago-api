# frozen_string_literal: true

class CreateCatalogWalletAppliedTaxes < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_wallet_applied_taxes, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :plan_wallet, type: :uuid, foreign_key: true, index: false
      t.references :catalog_wallet, type: :uuid, foreign_key: true, index: false
      t.references :tax, type: :uuid, null: false, foreign_key: true, index: true

      t.timestamps

      t.index %i[plan_wallet_id tax_id],
        unique: true,
        where: "plan_wallet_id IS NOT NULL",
        name: "index_catalog_wallet_applied_taxes_on_plan_wallet_and_tax"
      t.index %i[catalog_wallet_id tax_id],
        unique: true,
        where: "catalog_wallet_id IS NOT NULL",
        name: "index_catalog_wallet_applied_taxes_on_catalog_wallet_and_tax"

      t.check_constraint "num_nonnulls(plan_wallet_id, catalog_wallet_id) = 1",
        name: "catalog_wallet_applied_taxes_exactly_one_owner"
    end
  end
end
