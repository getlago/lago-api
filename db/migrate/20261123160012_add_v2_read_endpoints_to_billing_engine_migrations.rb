# frozen_string_literal: true

class AddV2ReadEndpointsToBillingEngineMigrations < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_engine_migrations, :v2_read_endpoints, :string, array: true, null: false, default: [], if_not_exists: true
  end
end
