# frozen_string_literal: true

class CreateExportsCustomersTaxes < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_customers_taxes
  end
end
