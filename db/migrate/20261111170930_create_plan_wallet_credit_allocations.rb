# frozen_string_literal: true

class CreatePlanWalletCreditAllocations < ActiveRecord::Migration[8.1]
  def change
    create_enum :plan_wallet_credit_allocation_trigger, %w[billing_cycle ongoing_balance]

    create_table :plan_wallet_credit_allocations, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :plan_wallet, type: :uuid, null: false, foreign_key: true, index: false
      t.references :product, type: :uuid, foreign_key: true, index: false
      t.references :product_filter, type: :uuid, foreign_key: true, index: false

      t.string :code, null: false
      t.enum :trigger, enum_type: :plan_wallet_credit_allocation_trigger, null: false
      t.integer :billing_cycles
      t.bigint :threshold_amount_cents
      t.bigint :credit_amount_cents, null: false
      t.bigint :purchase_amount_cents
      t.integer :priority, null: false, default: 50
      t.boolean :invoice_requires_successful_payment

      t.datetime :deleted_at

      t.timestamps

      t.index %i[plan_wallet_id code],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_plan_wallet_credit_allocations_on_wallet_and_code"
      t.index :plan_wallet_id,
        unique: true,
        where: "trigger = 'ongoing_balance' AND deleted_at IS NULL",
        name: "index_plan_wallet_credit_allocations_one_ongoing_balance"

      t.check_constraint "billing_cycles >= 1", name: "plan_wallet_credit_allocations_billing_cycles_positive"
      t.check_constraint "credit_amount_cents > 0", name: "plan_wallet_credit_allocations_credit_amount_positive"
      t.check_constraint <<~SQL.squish, name: "plan_wallet_credit_allocations_trigger_fields"
        CASE trigger
          WHEN 'billing_cycle' THEN num_nonnulls(product_id, product_filter_id) = 1
            AND num_nonnulls(threshold_amount_cents, purchase_amount_cents, invoice_requires_successful_payment) = 0
          WHEN 'ongoing_balance' THEN num_nonnulls(product_id, product_filter_id, billing_cycles) = 0
            AND num_nulls(threshold_amount_cents, purchase_amount_cents, invoice_requires_successful_payment) = 0
        END
      SQL
    end
  end
end
