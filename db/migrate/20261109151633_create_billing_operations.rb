# frozen_string_literal: true

class CreateBillingOperations < ActiveRecord::Migration[8.1]
  def up
    create_enum :billing_operation_causation_type, %w[
      contract_activation periodic_continuation contract_units_change late_payment
      rate_change configuration_change contract_termination
    ]
    create_enum :billing_operations_cancelled_causation_type, %w[contract_termination]

    create_table :billing_operations, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, type: :uuid
      t.references :contract_rate_card, null: false, type: :uuid
      t.references :invoice, type: :uuid
      t.string :action_type, null: false
      t.enum :causation_type, enum_type: :billing_operation_causation_type, null: false
      t.datetime :billing_at, null: false
      t.datetime :cancelled_at
      t.enum :cancelled_causation_type, enum_type: :billing_operations_cancelled_causation_type
      t.datetime :target_cycle_started_at, null: false
      t.datetime :processed_at
      t.timestamps

      t.index [:organization_id, :billing_at, :id], where: "processed_at IS NULL AND cancelled_at IS NULL", name: "index_pending_billing_operations_on_org_and_date"
      t.index [:organization_id, :customer_id, :billing_at, :id], where: "processed_at IS NULL AND cancelled_at IS NULL", name: "index_pending_billing_operations_on_org_customer_date"
    end
  end

  def down
    drop_table :billing_operations # rubocop:disable Lago/NoDropColumnOrTable
    drop_enum :billing_operations_cancelled_causation_type
    drop_enum :billing_operation_causation_type
  end
end
