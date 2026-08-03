# frozen_string_literal: true

class AddCsAdminToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :cs_admin, :boolean, default: false, null: false
  end
end
