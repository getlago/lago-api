# frozen_string_literal: true

class AddContractBillingRelations < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    reversible do |direction|
      direction.up do
        add_reference :contracts, :billing_entity, type: :uuid, index: {algorithm: :concurrently}, foreign_key: {validate: false}
        add_reference :contracts, :payment_method, type: :uuid, index: {algorithm: :concurrently}, foreign_key: {validate: false}
      end

      direction.down do
        remove_reference :contracts, :payment_method, foreign_key: true
        remove_reference :contracts, :billing_entity, foreign_key: true
      end
    end

    add_column :contracts, :purchase_order_number, :string
    add_column :contracts, :consolidate_invoice, :boolean, default: true, null: false
  end
end
