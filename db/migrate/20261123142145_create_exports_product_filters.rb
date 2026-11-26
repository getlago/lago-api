# frozen_string_literal: true

class CreateExportsProductFilters < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_product_filters
  end
end
