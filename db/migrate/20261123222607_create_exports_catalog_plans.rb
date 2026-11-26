# frozen_string_literal: true

class CreateExportsCatalogPlans < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_catalog_plans
  end
end
