# frozen_string_literal: true

class AddOrganizationIdFkToAdjustedFees < ActiveRecord::Migration[7.2]
  def change
    add_foreign_key :adjusted_fees, :organizations, validate: false
  end
end
