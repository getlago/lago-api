# frozen_string_literal: true

class AddDescriptionToUsageAttributionTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :usage_attribution_types, :description, :string
  end
end
