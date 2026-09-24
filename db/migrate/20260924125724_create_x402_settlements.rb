# frozen_string_literal: true

class CreateX402Settlements < ActiveRecord::Migration[8.0]
  def change
    create_enum :x402_settlement_kind, %w[credit_purchase invoice_payment]
    create_enum :x402_settlement_status, %w[pending settled failed]

    create_table :x402_settlements, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :x402_connection, null: false, foreign_key: true, type: :uuid
      t.references :customer, foreign_key: true, type: :uuid
      t.references :subscription, foreign_key: true, type: :uuid, index: false
      t.references :wallet_transaction, foreign_key: true, type: :uuid, index: false
      t.enum :kind, enum_type: :x402_settlement_kind, null: false
      t.enum :status, enum_type: :x402_settlement_status, null: false, default: "pending"
      t.string :network, null: false
      t.string :asset, null: false
      t.string :payer_address, null: false
      t.string :payee_address, null: false
      t.decimal :settled_amount_atomic, precision: 38, scale: 0, null: false
      t.bigint :settled_amount_cents, null: false
      t.string :transaction_hash
      t.datetime :reconcile_after
      t.string :payment_digest, null: false
      t.jsonb :purchase_settings
      t.jsonb :payload, null: false, default: {}
      t.string :error_reason
      t.timestamps

      t.index %i[organization_id payment_digest], unique: true, where: "status IN ('pending', 'settled')",
        name: "index_x402_settlements_on_organization_id_and_payment_digest"
      t.index %i[organization_id network transaction_hash], unique: true, where: "transaction_hash IS NOT NULL",
        name: "index_x402_settlements_on_org_network_and_transaction_hash"
      t.check_constraint "settled_amount_atomic > 0", name: "check_x402_settlements_amount_positive"
      t.check_constraint "status <> 'settled' OR transaction_hash IS NOT NULL", name: "check_x402_settlements_settled_has_hash"
      t.check_constraint "status <> 'pending' OR reconcile_after IS NOT NULL", name: "check_x402_settlements_pending_reconcile_after"
      t.check_constraint "kind <> 'credit_purchase' OR purchase_settings IS NOT NULL", name: "check_x402_settlements_purchase_settings"
      t.check_constraint "wallet_transaction_id IS NULL OR subscription_id IS NOT NULL", name: "check_x402_settlements_grant_subscription"
    end
  end
end
