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
      return result unless copyable?
      return shadow_organization_not_isolated_failure unless migration.shadow_organization_isolated?

      result.customer = find_shadow_customer || create_shadow_customer!
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :migration, :customer

    delegate :shadow_organization, to: :migration

    def copyable?
      migration.shadowing? && customer.organization_id == migration.organization_id
    end

    def shadow_organization_not_isolated_failure
      result.service_failure!(
        code: "shadow_organization_not_isolated",
        message: "shadow organization #{shadow_organization.id} has webhook endpoints, invoice emails or a dunning campaign"
      )
    end

    def find_shadow_customer
      shadow_organization.customers.find_by(external_id: customer.external_id)
    end

    def create_shadow_customer!
      creation = Customers::CreateService.call(**customer_input, organization_id: shadow_organization.id)
      return creation.customer if creation.success?

      concurrent_customer = find_shadow_customer if external_id_taken?(creation.error)
      concurrent_customer || raise(creation.error)
    end

    def external_id_taken?(error)
      error.is_a?(BaseService::ValidationFailure) && error.messages[:external_id]&.include?("value_already_exist")
    end

    def customer_input
      input = customer.slice(*CUSTOMER_ATTRIBUTES).symbolize_keys.compact_blank
      input[:timezone] = customer.applicable_timezone
      input[:billing_entity_code] = shadow_billing_entity_code
      input[:shipping_address] = shipping_address if shipping_address.any?
      input
    end

    # Each organization's default billing entity has its own code, so the two defaults are matched to each other, not by code.
    def shadow_billing_entity_code
      if customer.billing_entity_id == migration.organization.default_billing_entity&.id
        shadow_organization.default_billing_entity&.code
      else
        customer.billing_entity.code
      end
    end

    def shipping_address
      @shipping_address ||= SHIPPING_ATTRIBUTES.transform_values { |column| customer.public_send(column) }.compact_blank
    end
  end
end
