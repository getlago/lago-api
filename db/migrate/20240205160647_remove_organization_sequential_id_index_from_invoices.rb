# frozen_string_literal: true

class RemoveOrganizationSequentialIdIndexFromInvoices < ActiveRecord::Migration[7.0]
  def change
    remove_index :invoices, name: 'unique_organization_sequential_id'
  end
end
