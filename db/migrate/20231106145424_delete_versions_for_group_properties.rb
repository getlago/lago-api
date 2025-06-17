# frozen_string_literal: true

class DeleteVersionsForGroupProperties < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          DELETE FROM VERSIONS
          WHERE item_type = 'GroupProperty';
          SQL
        end
      end
    end
  end
end
