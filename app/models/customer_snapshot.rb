# frozen_string_literal: true

class CustomerSnapshot < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :invoice
  belongs_to :organization

  validates :invoice_id, uniqueness: {conditions: -> { where(deleted_at: nil) }}

  default_scope -> { kept }

  def billing_address
    {
      address_line1: address_line1,
      address_line2: address_line2,
      city: city,
      state: state,
      zipcode: zipcode,
      country: country
    }
  end

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
#  deleted_at                :datetime
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
#  index_customer_snapshots_on_deleted_at       (deleted_at)
#  index_customer_snapshots_on_invoice_id       (invoice_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_customer_snapshots_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#
