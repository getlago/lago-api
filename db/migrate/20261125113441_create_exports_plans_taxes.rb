# frozen_string_literal: true

class CreateExportsPlansTaxes < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_plans_taxes
  end
end
