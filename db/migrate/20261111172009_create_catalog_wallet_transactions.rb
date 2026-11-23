# frozen_string_literal: true

class CreateCatalogWalletTransactions < ActiveRecord::Migration[8.1]
  def change
    create_enum :catalog_wallet_transaction_direction, %w[inbound outbound]
    create_enum :catalog_wallet_transaction_status, %w[pending settled failed]
    create_enum :catalog_wallet_transaction_reason, %w[top_up credit_allocation invoice_void invoice_application void]
    create_enum :catalog_wallet_transaction_allocation_type, %w[billing_cycle ongoing_balance]

    create_table :catalog_wallet_transactions, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :catalog_wallet, type: :uuid, null: false, foreign_key: true, index: true
      t.references :credit_allocation, type: :uuid, foreign_key: {to_table: :catalog_wallet_credit_allocations}, index: true
      t.references :invoice, type: :uuid, foreign_key: true, index: true

      t.enum :direction, enum_type: :catalog_wallet_transaction_direction, null: false
      t.enum :status, enum_type: :catalog_wallet_transaction_status, null: false
      t.enum :reason, enum_type: :catalog_wallet_transaction_reason, null: false
      t.enum :allocation_type, enum_type: :catalog_wallet_transaction_allocation_type
      t.integer :priority, null: false, default: 50
      t.bigint :purchase_amount_cents
      t.bigint :credit_amount_cents, null: false
      t.bigint :remaining_credit_amount_cents
      t.boolean :invoice_requires_successful_payment
      t.datetime :source_cycle_started_at
      t.string :idempotency_key
      t.string :request_digest
      t.datetime :settled_at
      t.datetime :failed_at

      t.timestamps

      t.index %i[credit_allocation_id source_cycle_started_at],
        unique: true,
        where: "source_cycle_started_at IS NOT NULL",
        name: "index_catalog_wallet_transactions_on_grant_occurrence"
      t.index :catalog_wallet_id,
        unique: true,
        where: "allocation_type = 'ongoing_balance' AND status = 'pending'",
        name: "index_catalog_wallet_transactions_one_pending_ongoing_balance"
      t.index %i[catalog_wallet_id idempotency_key],
        unique: true,
        where: "idempotency_key IS NOT NULL",
        name: "index_catalog_wallet_transactions_on_wallet_and_idempotency_key"
      t.index "catalog_wallet_id, priority, (purchase_amount_cents > 0), created_at, id",
        where: "direction = 'inbound' AND status = 'settled' AND remaining_credit_amount_cents > 0",
        name: "index_catalog_wallet_transactions_in_spending_order"

      t.check_constraint "remaining_credit_amount_cents >= 0",
        name: "catalog_wallet_transactions_remaining_non_negative"
      t.check_constraint "remaining_credit_amount_cents <= credit_amount_cents",
        name: "catalog_wallet_transactions_remaining_within_credit"
      t.check_constraint "credit_amount_cents > 0 AND purchase_amount_cents >= 0",
        name: "catalog_wallet_transactions_amounts_positive"
      t.check_constraint <<~SQL.squish, name: "catalog_wallet_transactions_direction_fields"
        CASE direction
          WHEN 'inbound' THEN reason IN ('top_up', 'credit_allocation', 'invoice_void')
            AND num_nulls(purchase_amount_cents, remaining_credit_amount_cents) = 0
          WHEN 'outbound' THEN reason IN ('invoice_application', 'void')
            AND num_nonnulls(purchase_amount_cents, remaining_credit_amount_cents) = 0
        END
      SQL
      t.check_constraint <<~SQL.squish, name: "catalog_wallet_transactions_allocation_fields"
        CASE reason
          WHEN 'credit_allocation' THEN num_nulls(credit_allocation_id, allocation_type) = 0
            AND (allocation_type = 'billing_cycle') = (source_cycle_started_at IS NOT NULL)
          ELSE num_nonnulls(credit_allocation_id, allocation_type, source_cycle_started_at) = 0
        END
      SQL
      t.check_constraint "(status = 'settled') = (settled_at IS NOT NULL)",
        name: "catalog_wallet_transactions_settled_at_with_status"
      t.check_constraint "(status = 'failed') = (failed_at IS NOT NULL)",
        name: "catalog_wallet_transactions_failed_at_with_status"
      t.check_constraint "request_digest ~ '^[0-9a-f]{64}$'",
        name: "catalog_wallet_transactions_request_digest_format"
    end
  end
end
