# frozen_string_literal: true

class RemoveStatusFromGroups < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE groups
          SET deleted_at = updated_at
          WHERE deleted_at IS NULL
          AND groups.status = 1
          SQL
        end
      end

      remove_column :groups, :status, :integer, default: 0
    end
  end
end
