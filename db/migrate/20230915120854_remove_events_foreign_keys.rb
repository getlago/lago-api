# frozen_string_literal: true

class RemoveEventsForeignKeys < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :events, :customers
    remove_foreign_key :events, :organizations
    remove_foreign_key :events, :subscriptions
  end
end
