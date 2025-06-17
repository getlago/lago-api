# frozen_string_literal: true

class AddOrganizationIdFkToFees < ActiveRecord::Migration[7.1]
  def change
    add_foreign_key :fees, :organizations, validate: false
  end
end
