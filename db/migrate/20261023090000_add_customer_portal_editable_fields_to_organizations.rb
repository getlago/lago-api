# frozen_string_literal: true

class AddCustomerPortalEditableFieldsToOrganizations < ActiveRecord::Migration[8.1]
  DEFAULT_FIELDS = %w[
    customer_type
    document_locale
    email
    firstname
    lastname
    legal_name
    name
    address_line1
    address_line2
    city
    state
    shipping_address
  ].freeze

  def change
    add_column :organizations, :customer_portal_editable_fields, :string, array: true, default: DEFAULT_FIELDS, null: false, if_not_exists: true
  end
end
