# frozen_string_literal: true

class DropFlatFiltersView < ActiveRecord::Migration[8.0]
  def change
    drop_view :flat_filters, revert_to_version: 5
  end
end
