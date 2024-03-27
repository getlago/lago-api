# frozen_string_literal: true

class RemoveOrganizationSequentialIdIndexFromInvoices < ActiveRecord::Migration[7.0]
  def change
    remove_index :invoices,
      "organization_id, organization_sequential_id, (date_trunc('month', created_at)::date)",
      name: "unique_organization_sequential_id"
  end
end
