# frozen_string_literal: true

class ValidateForeignKeyBillingEntitiesOnInvoices < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    # Validate foreign key in a separate transaction
    validate_foreign_key :invoices, :billing_entities
  end
end
