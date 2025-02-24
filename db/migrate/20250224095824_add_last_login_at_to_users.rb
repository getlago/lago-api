# frozen_string_literal: true

class AddLastLoginAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :last_login_at, :datetime, null: true
    add_column :users, :last_login_method, :integer, null: true
  end
end
