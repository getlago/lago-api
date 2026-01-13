# frozen_string_literal: true

class CreateExportsEntitlementValues < ActiveRecord::Migration[8.0]
  def change
    create_view :exports_entitlement_entitlement_values
  end
end
