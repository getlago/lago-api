# frozen_string_literal: true

# One-time, idempotent backfill for the multi-connection groundwork (ING-452).
#
# For a single organization it:
#   * sets `code` on payment_provider_customers   (from payment_provider.code)   where code IS NULL
#   * sets `code` on integration_customers        (from integration.code)        where code IS NULL
#   * sets `category` on integration_customers    (derived from the STI type)    where category IS NULL
#   * marks the single existing connection of each category `is_default = true`
#
# Idempotent: codes/categories only touch NULL rows; defaults only apply when the
# (customer, category) group has no default yet. Re-running is a no-op once complete.
#
# Safety: production data was verified to hold at most one connection per category
# per customer. Should a group ever contain more than one, we skip it and count it
# as a conflict instead of writing two defaults.
module MultiCustomerConnections
  class BackfillConnectionCodesService < BaseService
    Result = BaseResult[:summary]

    CATEGORY_BY_TYPE = {
      "IntegrationCustomers::AnrokCustomer" => "tax",
      "IntegrationCustomers::AvalaraCustomer" => "tax",
      "IntegrationCustomers::NetsuiteCustomer" => "accounting",
      "IntegrationCustomers::XeroCustomer" => "accounting",
      "IntegrationCustomers::HubspotCustomer" => "crm",
      "IntegrationCustomers::SalesforceCustomer" => "crm"
    }.freeze

    def initialize(organization:, dry_run: true, batch_size: 1000)
      @organization = organization
      @dry_run = dry_run
      @batch_size = batch_size
      @summary = Hash.new(0)
      super
    end

    def call
      backfill_payment_codes
      backfill_integration_codes_and_categories
      backfill_payment_defaults
      backfill_integration_defaults

      result.summary = summary.dup
      result
    end

    private

    attr_reader :organization, :dry_run, :batch_size, :summary

    def backfill_payment_codes
      scope = PaymentProviderCustomers::BaseCustomer
        .where(organization_id: organization.id, code: nil)
        .where.not(payment_provider_id: nil)
        .includes(:payment_provider)

      scope.find_each(batch_size:) do |pp_customer|
        code = pp_customer.payment_provider&.code
        next if code.blank?

        summary[:payment_codes_set] += 1
        pp_customer.update_columns(code:) unless dry_run # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def backfill_integration_codes_and_categories
      scope = IntegrationCustomers::BaseCustomer
        .where(organization_id: organization.id)
        .includes(:integration)

      scope.find_each(batch_size:) do |int_customer|
        updates = {}
        updates[:code] = int_customer.integration&.code if int_customer.code.nil?
        updates[:category] = CATEGORY_BY_TYPE[int_customer.type] if int_customer.category.nil?
        updates.delete(:code) if updates[:code].blank?
        updates.delete(:category) if updates[:category].blank?
        next if updates.empty?

        summary[:integration_codes_set] += 1 if updates.key?(:code)
        summary[:integration_categories_set] += 1 if updates.key?(:category)
        int_customer.update_columns(updates) unless dry_run # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def backfill_payment_defaults
      grouped = PaymentProviderCustomers::BaseCustomer
        .where(organization_id: organization.id)
        .group_by(&:customer_id)

      grouped.each_value do |connections|
        next if connections.any?(&:is_default?)

        if connections.one?
          summary[:payment_defaults_set] += 1
          connections.first.update_columns(is_default: true) unless dry_run # rubocop:disable Rails/SkipsModelValidations
        else
          summary[:payment_default_conflicts] += 1
        end
      end
    end

    def backfill_integration_defaults
      grouped = IntegrationCustomers::BaseCustomer
        .where(organization_id: organization.id)
        .group_by { |ic| [ic.customer_id, CATEGORY_BY_TYPE[ic.type]] }

      grouped.each do |(_customer_id, category), connections|
        next if category.nil? # unknown STI type, nothing to route
        next if connections.any?(&:is_default?)

        if connections.one?
          summary[:integration_defaults_set] += 1
          connections.first.update_columns(is_default: true) unless dry_run # rubocop:disable Rails/SkipsModelValidations
        else
          summary[:integration_default_conflicts] += 1
        end
      end
    end
  end
end
