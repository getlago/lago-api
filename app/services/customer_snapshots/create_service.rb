# frozen_string_literal: true

module CustomerSnapshots
  class CreateService < BaseService
    Result = BaseResult[:customer_snapshot]
    def initialize(invoice:, force: false)
      @invoice = invoice
      @force = force
      super
    end

    def call
      return result if invoice.customer_snapshot && !force

      if force && invoice.customer_snapshot
        invoice.customer_snapshot.destroy!
      end

      customer_snapshot = invoice.create_customer_snapshot!(
        organization: invoice.organization,
        display_name: customer.display_name,
        firstname: customer.firstname,
        lastname: customer.lastname,
        email: customer.email,
        phone: customer.phone,
        url: customer.url,
        tax_identification_number: customer.tax_identification_number,
        applicable_timezone: customer.applicable_timezone,
        address_line1: customer.address_line1,
        address_line2: customer.address_line2,
        city: customer.city,
        state: customer.state,
        zipcode: customer.zipcode,
        country: customer.country,
        legal_name: customer.legal_name,
        legal_number: customer.legal_number,
        shipping_address_line1: customer.shipping_address_line1,
        shipping_address_line2: customer.shipping_address_line2,
        shipping_city: customer.shipping_city,
        shipping_state: customer.shipping_state,
        shipping_zipcode: customer.shipping_zipcode,
        shipping_country: customer.shipping_country
      )

      result.customer_snapshot = customer_snapshot
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :force
    delegate :customer, to: :invoice
  end
end
