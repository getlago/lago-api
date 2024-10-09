# frozen_string_literal: true

module CustomerPortal
  class CustomerUpdateService < BaseService
    def initialize(customer:, args:)
      @customer = customer
      @args = args

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      ActiveRecord::Base.transaction do
        customer.customer_type = args[:customer_type] if args.key?(:customer_type)
        customer.name = args[:name] if args.key?(:name)
        customer.firstname = args[:firstname] if args.key?(:firstname)
        customer.lastname = args[:lastname] if args.key?(:lastname)
        customer.legal_name = args[:legal_name] if args.key?(:legal_name)
        customer.tax_identification_number = args[:tax_identification_number] if args.key?(:tax_identification_number)
        customer.email = args[:email] if args.key?(:email)

        customer.document_locale = args[:document_locale] if args.key?(:document_locale)

        customer.address_line1 = args[:address_line1] if args.key?(:address_line1)
        customer.address_line2 = args[:address_line2] if args.key?(:address_line2)
        customer.zipcode = args[:zipcode] if args.key?(:zipcode)
        customer.city = args[:city] if args.key?(:city)
        customer.state = args[:state] if args.key?(:state)
        customer.country = args[:country]&.upcase if args.key?(:country)

        shipping_address = args[:shipping_address]&.to_h || {}
        customer.shipping_address_line1 = shipping_address[:address_line1] if shipping_address.key?(:address_line1)
        customer.shipping_address_line2 = shipping_address[:address_line2] if shipping_address.key?(:address_line2)
        customer.shipping_zipcode = shipping_address[:zipcode] if shipping_address.key?(:zipcode)
        customer.shipping_city = shipping_address[:city] if shipping_address.key?(:city)
        customer.shipping_state = shipping_address[:state] if shipping_address.key?(:state)
        customer.shipping_country = shipping_address[:country]&.upcase if shipping_address.key?(:country)

        customer.save!
        customer.reload

        tax_codes = []
        if customer.organization.eu_tax_management
          # This service does not return a 'result' object but a string
          tax_codes << Customers::EuAutoTaxesService.call(customer:)
        end

        if tax_codes.present?
          taxes_result = Customers::ApplyTaxesService.call(customer:, tax_codes:)
          taxes_result.raise_if_error!
        end
      end

      result.customer = customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :args
  end
end
