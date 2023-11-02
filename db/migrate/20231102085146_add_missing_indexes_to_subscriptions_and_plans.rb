# frozen_string_literal: true

class AddMissingIndexesToSubscriptionsAndPlans < ActiveRecord::Migration[7.0]
  def change
    add_index :subscriptions, :started_at
    add_index :subscriptions, :status

    add_index :plans, :created_at
  end
end
