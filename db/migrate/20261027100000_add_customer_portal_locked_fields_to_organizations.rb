# frozen_string_literal: true

class AddCustomerPortalLockedFieldsToOrganizations < ActiveRecord::Migration[8.1]
  DEFAULT_LOCKED_FIELDS = %w[country zipcode tax_identification_number].freeze

  def change
    add_column :organizations, :customer_portal_locked_fields, :string, array: true, default: DEFAULT_LOCKED_FIELDS, null: false, if_not_exists: true
  end
end
