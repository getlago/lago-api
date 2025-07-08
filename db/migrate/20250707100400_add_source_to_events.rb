# frozen_string_literal: true

class AddSourceToEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :events, :source, :string, default: 'usage', null: false
    
    add_index :events, :source, algorithm: :concurrently
    add_index :events, [:organization_id, :source], algorithm: :concurrently
    add_index :events, [:external_subscription_id, :source], algorithm: :concurrently
  end
end 