class UpdateOrganizationSequentialIdIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index :invoices, name: :unique_organization_sequential_id
    add_index :invoices,
              "organization_id, organization_sequential_id, (date_trunc('month', created_at)::date)",
              name: 'unique_organization_sequential_id',
              unique: true,
              where: 'organization_sequential_id != 0'
  end
end
