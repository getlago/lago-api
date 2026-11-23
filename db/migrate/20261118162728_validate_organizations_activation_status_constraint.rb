# frozen_string_literal: true

class ValidateOrganizationsActivationStatusConstraint < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :organizations, name: "check_organizations_on_activation_status"
  end
end
