# frozen_string_literal: true

module CustomerDataSnapshotting
  extend ActiveSupport::Concern

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

  included do
    before_save :snapshot_customer_data, if: -> { status_changed_to_finalized? }

    SNAPSHOTTED_ATTRIBUTES.each do |attribute|
      define_method("customer_#{attribute}") do
        customer_data_snapshotted_at? ? self[:"customer_#{attribute}"] : customer.public_send(attribute)
      end
    end

    def customer_shipping_address
      {
        address_line1: customer_shipping_address_line1,
        address_line2: customer_shipping_address_line2,
        city: customer_shipping_city,
        state: customer_shipping_state,
        zipcode: customer_shipping_zipcode,
        country: customer_shipping_country
      }
    end
  end

  private

  def snapshot_customer_data(force: false)
    return unless status_changed_to_finalized? || force

    self.customer_data_snapshotted_at = Time.current

    SNAPSHOTTED_ATTRIBUTES.each do |attribute|
      self[:"customer_#{attribute}"] = customer.public_send(attribute)
    end
  end
end
