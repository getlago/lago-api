# frozen_string_literal: true

class AddUniqueIdToSubscriptions < ActiveRecord::Migration[7.0]
  def up
    add_column :subscriptions, :unique_id, :string
    safety_assured do
      change_column_null :subscriptions, :unique_id, false
    end
  end

  def down
    remove_column :subscriptions, :unique_id, :string
  end
end
