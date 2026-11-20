# frozen_string_literal: true

module BillingEngineMigrations
  class CopyCustomerService < BaseService
    Result = BaseResult[:customer]

    CUSTOMER_ATTRIBUTES = %i[
      external_id name firstname lastname customer_type email phone url legal_name legal_number
      tax_identification_number address_line1 address_line2 city state zipcode country currency
    ].freeze

    SHIPPING_ATTRIBUTES = {
      address_line1: :shipping_address_line1,
      address_line2: :shipping_address_line2,
      city: :shipping_city,
      state: :shipping_state,
      zipcode: :shipping_zipcode,
      country: :shipping_country
    }.freeze

    def initialize(migration:, customer:)
      @migration = migration
      @customer = customer
      super
    end

    def call
      return result unless migration.shadowing?
      return result unless customer.organization_id == migration.organization_id

      existing = find_shadow_customer
      if existing
        result.customer = existing
        return result
      end

      creation = Customers::CreateService.call(**customer_input, organization_id: shadow_organization.id)
      if creation.success?
        result.customer = creation.customer
      elsif external_id_taken?(creation.error) && (existing = find_shadow_customer)
        result.customer = existing
      else
        return result.fail_with_error!(creation.error)
      end

      result
    end

    private

    attr_reader :migration, :customer

    delegate :shadow_organization, to: :migration

    def find_shadow_customer
      shadow_organization.customers.find_by(external_id: customer.external_id)
    end

    def external_id_taken?(error)
      error.is_a?(BaseService::ValidationFailure) && error.messages[:external_id]&.include?("value_already_exist")
    end

    def customer_input
      input = customer.slice(*CUSTOMER_ATTRIBUTES).symbolize_keys.compact_blank
      input[:timezone] = customer.applicable_timezone
      input[:billing_entity_code] = customer.billing_entity.code
      shipping_address = SHIPPING_ATTRIBUTES.transform_values { |column| customer.public_send(column) }.compact_blank
      input[:shipping_address] = shipping_address if shipping_address.any?
      input
    end
  end
end
