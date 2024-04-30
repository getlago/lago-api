# frozen_string_literal: true

class AddRoleToInvite < ActiveRecord::Migration[7.0]
  def change
    add_column :invites, :role, :integer, null: false, default: 0
  end
end
