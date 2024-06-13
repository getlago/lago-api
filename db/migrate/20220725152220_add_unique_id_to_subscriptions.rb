# frozen_string_literal: true

class AddUniqueIdToSubscriptions < ActiveRecord::Migration[7.0]
  def up
    add_column :subscriptions, :unique_id, :string
    change_column_null :subscriptions, :unique_id, false
  end

  def down
    remove_column :subscriptions, :unique_id, :string
  end
end
