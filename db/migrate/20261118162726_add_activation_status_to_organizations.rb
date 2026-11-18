# frozen_string_literal: true

class AddActivationStatusToOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_enum :organization_activation_status, %w[pending_payment_method active]

    # A constant default keeps this metadata-only: existing organizations read as active.
    add_column :organizations, :activation_status, :enum, enum_type: :organization_activation_status,
      default: "active", null: false, if_not_exists: true
    add_column :organizations, :activated_at, :datetime, if_not_exists: true

    add_check_constraint :organizations,
      "activation_status = 'active' OR (self_serve AND environment = 'production' AND activated_at IS NULL)",
      name: "check_organizations_on_activation_status", validate: false, if_not_exists: true
  end
end
