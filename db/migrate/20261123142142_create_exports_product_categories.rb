# frozen_string_literal: true

class CreateExportsProductCategories < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_product_categories
  end
end
