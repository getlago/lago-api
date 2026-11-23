# frozen_string_literal: true

class CreateExportsProducts < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_products
  end
end
