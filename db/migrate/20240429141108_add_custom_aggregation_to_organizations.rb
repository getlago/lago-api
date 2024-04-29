# frozen_string_literal: true

class AddCustomAggregationToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :custom_aggregation, :boolean, default: false
  end
end
