# frozen_string_literal: true

class AddDeletedAtToPaymentProviders < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :payment_providers, :deleted_at, :datetime
    remove_index :payment_providers, %i[code organization_id]
    add_index :payment_providers, %i[code organization_id], unique: true, where: 'deleted_at IS NULL', algorithm: :concurrently
  end

  def down
    remove_column :payment_providers, :deleted_at
    remove_index :payment_providers, %i[code organization_id]
    add_index :payment_providers, %i[code organization_id], unique: true, algorithm: :concurrently
  end
end
