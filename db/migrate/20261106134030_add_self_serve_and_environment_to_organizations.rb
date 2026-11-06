# frozen_string_literal: true

class AddSelfServeAndEnvironmentToOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_enum :organization_environment, %w[production sandbox]

    # Constant defaults keep these metadata-only: existing organizations read as production, not self-serve, unlinked.
    add_column :organizations, :self_serve, :boolean, default: false, null: false, if_not_exists: true
    add_column :organizations, :environment, :enum, enum_type: :organization_environment, default: "production",
      null: false, if_not_exists: true
    add_column :organizations, :production_organization_id, :uuid, if_not_exists: true

    add_foreign_key :organizations, :organizations, column: :production_organization_id, validate: false,
      if_not_exists: true
    add_check_constraint :organizations, "production_organization_id IS NULL OR production_organization_id <> id",
      name: "check_organizations_on_production_organization_not_self", validate: false, if_not_exists: true
    add_check_constraint :organizations,
      "(environment = 'production' AND production_organization_id IS NULL) OR " \
      "(environment = 'sandbox' AND production_organization_id IS NOT NULL)",
      name: "check_organizations_on_environment_link", validate: false, if_not_exists: true
  end
end
