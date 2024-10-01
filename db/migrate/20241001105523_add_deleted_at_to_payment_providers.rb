# frozen_string_literal: true

class AddDeletedAtToPaymentProviders < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    safety_assured do
      add_column :payment_providers, :deleted_at, :datetime

      remove_index :payment_providers, %i[code organization_id]
      add_index :payment_providers, %i[code organization_id], unique: true, where: 'deleted_at IS NULL'
    end
  end

  def down
    safety_assured do
      remove_column :payment_providers, :deleted_at
      remove_index :payment_providers, %i[code organization_id]
      add_index :payment_providers, %i[code organization_id], unique: true
    end
  end
end
