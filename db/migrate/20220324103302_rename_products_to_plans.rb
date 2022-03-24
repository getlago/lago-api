# frozen_string_literal: true

class RenameProductsToPlans < ActiveRecord::Migration[7.0]
  def change
    rename_table :products, :plans
  end
end
