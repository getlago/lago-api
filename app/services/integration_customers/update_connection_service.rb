# frozen_string_literal: true

module IntegrationCustomers
  class UpdateConnectionService < ::BaseService
    NON_SYNCING_TYPES = %w[
      IntegrationCustomers::AnrokCustomer
      IntegrationCustomers::SalesforceCustomer
    ].freeze

    Result = BaseResult[:integration_customer]

    def initialize(integration_customer:, params:)
      @integration_customer = integration_customer
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "integration_customer") unless integration_customer

      integration_customer.update!(code: params[:code]) if params.key?(:code)

      sync_provider_customer if sync_provider_customer?

      result.integration_customer = integration_customer.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :integration_customer, :params

    delegate :customer, :integration, to: :integration_customer

    def sync_provider_customer?
      return false if customer.partner_account?

      NON_SYNCING_TYPES.exclude?(integration_customer.type)
    end

    def integration_customer_params
      @integration_customer_params ||= params
        .slice(:external_customer_id, :subsidiary_id, :sync_with_provider, :targeted_object)
        .merge(integration_type: integration.provider_key, integration_code: integration.code)
    end

    def sync_provider_customer
      IntegrationCustomers::UpdateJob.perform_later(
        integration_customer_params:,
        integration:,
        integration_customer:
      )
    end
  end
end
