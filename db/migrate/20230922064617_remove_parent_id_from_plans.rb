# frozen_string_literal: true

class RemoveParentIdFromPlans < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE plans
          SET parent_id = NULL
        SQL
      end
    end
  end
end
