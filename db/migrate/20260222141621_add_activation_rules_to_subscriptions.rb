# frozen_string_literal: true

class AddActivationRulesToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :activation_rules, :jsonb, null: true, default: nil
    add_column :subscriptions, :activating_at, :datetime, null: true
  end
end
