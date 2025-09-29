# frozen_string_literal: true

class CustomerSnapshot < ApplicationRecord
  SNAPSHOTTED_ATTRIBUTES = %i[
    display_name
    firstname
    lastname
    email
    phone
    url
    tax_identification_number
    applicable_timezone
    address_line1
    address_line2
    city
    state
    zipcode
    country
    legal_name
    legal_number
    shipping_address_line1
    shipping_address_line2
    shipping_city
    shipping_state
    shipping_zipcode
    shipping_country
  ].freeze

  belongs_to :invoice
  belongs_to :organization

  validates :invoice_id, uniqueness: true

  def shipping_address
    {
      address_line1: shipping_address_line1,
      address_line2: shipping_address_line2,
      city: shipping_city,
      state: shipping_state,
      zipcode: shipping_zipcode,
      country: shipping_country
    }
  end
end

# == Schema Information
#
# Table name: customer_snapshots
#
#  id                        :uuid             not null, primary key
#  address_line1             :string
#  address_line2             :string
#  applicable_timezone       :string
#  city                      :string
#  country                   :string
#  display_name              :string
#  email                     :string
#  firstname                 :string
#  lastname                  :string
#  legal_name                :string
#  legal_number              :string
#  phone                     :string
#  shipping_address_line1    :string
#  shipping_address_line2    :string
#  shipping_city             :string
#  shipping_country          :string
#  shipping_state            :string
#  shipping_zipcode          :string
#  state                     :string
#  tax_identification_number :string
#  url                       :string
#  zipcode                   :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  invoice_id                :uuid             not null
#  organization_id           :uuid             not null
#
# Indexes
#
#  index_customer_snapshots_on_invoice_id       (invoice_id)
#  index_customer_snapshots_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#
