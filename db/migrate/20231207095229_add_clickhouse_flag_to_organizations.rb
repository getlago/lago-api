# frozen_string_literal: true

class AddClickhouseFlagToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :clickhouse_aggregation, :boolean, default: false, null: false
  end
end
