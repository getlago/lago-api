# frozen_string_literal: true

class ValidateIntegrationResourcesOrganizationsForeignKey < ActiveRecord::Migration[7.2]
  def change
    validate_foreign_key :integration_resources, :organizations
  end
end
