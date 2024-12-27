# frozen_string_literal: true

class AddCodeUniquenessConstraintOnInvoiceCustomSections < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :invoice_custom_sections, %i[organization_id code], unique: true, algorithm: :concurrently
    add_index :invoice_custom_sections, %i[organization_id code], unique: true, where: 'deleted_at IS NULL', algorithm: :concurrently
  end
end
