# frozen_string_literal: true

class ValidateChargeFilterValuesOrganizationsForeignKey < ActiveRecord::Migration[7.2]
  def change
    validate_foreign_key :charge_filter_values, :organizations
  end
end
