# frozen_string_literal: true

class AddEndingAtToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :ending_at, :datetime, null: true
  end
end
