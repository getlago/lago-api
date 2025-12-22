# frozen_string_literal: true

class RemoveRoleFromInvites < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      remove_column :invites, :role, :integer, default: 0, null: false
    end
  end
end
