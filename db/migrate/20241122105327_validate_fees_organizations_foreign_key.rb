# frozen_string_literal: true

class ValidateFeesOrganizationsForeignKey < ActiveRecord::Migration[7.1]
  def change
    validate_foreign_key :fees, :organizations
  end
end
