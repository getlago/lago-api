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

    COPIED_COLUMNS = [*CUSTOMER_ATTRIBUTES, *SHIPPING_ATTRIBUTES.values, :timezone, :billing_entity_id].map(&:to_s).freeze

    def initialize(migration:, customer:)
      @migration = migration
      @customer = customer
      super
    end

    def call
      return result unless copyable?
      return shadow_organization_not_isolated_failure unless migration.shadow_organization_isolated?

      # A session lock: inside a transaction, the unique violation of a concurrent create would abort it.
      Customers::LockService.call(customer:, scope: :shadow_copy, transaction: false) { copy_latest_customer! }
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

    def copy_latest_customer!
      @customer = Customer.find_by(id: customer.id, organization_id: migration.organization_id)

      if customer
        result.customer = copy_to_shadow_customer!
      else
        result.not_found_failure!(resource: "customer")
      end
    end

    def copy_to_shadow_customer!
      shadow_customer = find_shadow_customer
      shadow_customer ? update_shadow_customer!(shadow_customer) : create_shadow_customer!
    end

    def find_shadow_customer
      shadow_organization.customers.find_by(external_id: customer.external_id)
    end

    def create_shadow_customer!
      creation = Customers::CreateService.call(**creation_input, organization_id: shadow_organization.id)
      return creation.customer if creation.success?

      concurrent_customer = find_shadow_customer if external_id_taken?(creation.error)
      concurrent_customer ? update_shadow_customer!(concurrent_customer) : raise(creation.error)
    end

    def update_shadow_customer!(shadow_customer)
      changes = changed_input(shadow_customer)

      if changes.empty?
        shadow_customer
      else
        Customers::UpdateService.call!(customer: shadow_customer, args: changes).customer
      end
    end

    def external_id_taken?(error)
      error.is_a?(BaseService::ValidationFailure) && error.messages[:external_id]&.include?("value_already_exist")
    end

    def creation_input
      input = source_attributes.compact
      shipping = shipping_address(customer).compact
      input[:shipping_address] = shipping if shipping.any?
      input
    end

    def changed_input(shadow_customer)
      current = copied_attributes(shadow_customer, timezone: shadow_customer.timezone)
      input = source_attributes.reject { |key, value| current[key] == value }

      current_shipping = shipping_address(shadow_customer)
      shipping = shipping_address(customer).reject { |key, value| current_shipping[key] == value }
      input[:shipping_address] = shipping if shipping.any?
      input
    end

    def source_attributes
      @source_attributes ||= copied_attributes(customer, timezone: customer.applicable_timezone)
        .merge(billing_entity_code: shadow_billing_entity_code)
    end

    # Each organization's default billing entity has its own code: a customer of the V1 default goes on the shadow
    # default when the shadow organization has no billing entity with that code.
    def shadow_billing_entity_code
      code = customer.billing_entity&.code

      if on_v1_default_billing_entity? && !shadow_organization.billing_entities.exists?(code:)
        shadow_organization.default_billing_entity&.code
      else
        code
      end
    end

    def on_v1_default_billing_entity?
      customer.billing_entity_id == BillingEntity.active.where(organization_id: migration.organization_id).order(:created_at).pick(:id)
    end

    # Blank and nil are the same value, so a V1 empty string never rewrites a shadow nil.
    def copied_attributes(record, timezone:)
      record.slice(*CUSTOMER_ATTRIBUTES).symbolize_keys
        .merge(timezone:, billing_entity_code: record.billing_entity&.code)
        .transform_values(&:presence)
    end

    def shipping_address(record)
      SHIPPING_ATTRIBUTES.transform_values { |column| record.public_send(column).presence }
    end
  end
end
