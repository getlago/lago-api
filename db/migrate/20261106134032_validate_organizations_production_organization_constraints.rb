# frozen_string_literal: true

class ValidateOrganizationsProductionOrganizationConstraints < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :organizations, column: :production_organization_id
    validate_check_constraint :organizations, name: "check_organizations_on_production_organization_not_self"
    validate_check_constraint :organizations, name: "check_organizations_on_environment_link"
  end
end
