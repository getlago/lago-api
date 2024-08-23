# frozen_string_literal: true

class AddUniqueIndexOnInvoiceOrganizationSequentialId < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_index :invoices,
        "organization_id, organization_sequential_id, date_trunc('month'::text, created_at)",
        name: 'unique_organization_sequential_id',
        unique: true,
        where: 'organization_sequential_id != 0'
    end
  end
end
