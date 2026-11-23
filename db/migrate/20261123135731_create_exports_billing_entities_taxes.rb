# frozen_string_literal: true

class CreateExportsBillingEntitiesTaxes < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_billing_entities_taxes
  end
end
