# frozen_string_literal: true

class CreateExportsPricingUnits < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_pricing_units
  end
end
