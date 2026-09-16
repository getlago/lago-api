# frozen_string_literal: true

class AddContractBillingRelations < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    reversible do |direction|
      direction.up do
        # Non-transactional DDL can leave a reference partially created after a failure.
        add_column :contracts, :billing_entity_id, :uuid, if_not_exists: true
        add_index :contracts, :billing_entity_id, algorithm: :concurrently, if_not_exists: true
        add_foreign_key :contracts, :billing_entities, column: :billing_entity_id, validate: false, if_not_exists: true

        add_column :contracts, :payment_method_id, :uuid, if_not_exists: true
        add_index :contracts, :payment_method_id, algorithm: :concurrently, if_not_exists: true
        add_foreign_key :contracts, :payment_methods, column: :payment_method_id, validate: false, if_not_exists: true
      end

      direction.down do
        remove_reference :contracts, :payment_method, foreign_key: true
        remove_reference :contracts, :billing_entity, foreign_key: true
      end
    end

    add_column :contracts, :purchase_order_number, :string, if_not_exists: true
    add_column :contracts, :consolidate_invoice, :boolean, default: true, null: false, if_not_exists: true
  end
end
