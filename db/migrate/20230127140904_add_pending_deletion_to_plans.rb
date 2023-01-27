# frozen_string_literal: true

class AddPendingDeletionToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :pending_deletion, :boolean, null: false, default: false
  end
end
