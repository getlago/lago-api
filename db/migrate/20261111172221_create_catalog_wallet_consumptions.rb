# frozen_string_literal: true

class CreateCatalogWalletConsumptions < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_wallet_consumptions, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :outbound_transaction, type: :uuid, null: false, foreign_key: {to_table: :catalog_wallet_transactions}, index: false
      t.references :inbound_transaction, type: :uuid, null: false, foreign_key: {to_table: :catalog_wallet_transactions}, index: true
      t.references :fee, type: :uuid, foreign_key: true, index: {where: "fee_id IS NOT NULL"}

      t.bigint :credit_amount_cents, null: false

      t.timestamps

      t.index %i[outbound_transaction_id inbound_transaction_id fee_id],
        unique: true,
        nulls_not_distinct: true,
        name: "index_catalog_wallet_consumptions_on_outbound_inbound_and_fee"

      t.check_constraint "credit_amount_cents > 0", name: "catalog_wallet_consumptions_credit_amount_positive"
    end
  end
end
