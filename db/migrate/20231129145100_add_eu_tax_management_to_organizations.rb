# frozen_string_literal: true

class AddEuTaxManagementToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :eu_tax_management, :boolean, default: false
  end
end
