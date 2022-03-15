class ChangeMembershipsRoleDatatype < ActiveRecord::Migration[7.0]
  def change
    remove_column :memberships, :role
    add_column :memberships, :role, :integer, default: 0, null: false
  end
end
