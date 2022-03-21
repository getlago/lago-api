class ChangeProductOrganizationsIdColumnName < ActiveRecord::Migration[7.0]
  def change
    rename_column :products, :organizations_id, :organization_id
  end
end
