# frozen_string_literal: true

module IntegrationCustomers
  class CreateConnectionService < ::BaseService
    Result = BaseResult[:integration_customer]

    def initialize(customer:, params:)
      @customer = customer
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "integration") unless integration
      return result.single_validation_failure!(field: :integration_id, error_code: "value_is_invalid") if category.blank?
      return result if customer.partner_account?
      return result unless create_integration_customer?

      first_connection = customer.integration_customers.where(category:).none?

      ActiveRecord::Base.transaction do
        @integration_customer = create_integration_customer
        next unless integration_customer

        integration_customer.code = params[:code].presence || integration.code
        integration_customer.category = category
        integration_customer.is_default = true if first_connection
        integration_customer.save!
      end

      return result unless integration_customer

      result.integration_customer = integration_customer.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :customer, :params, :integration_customer

    def integration
      return @integration if defined?(@integration)

      @integration = customer.organization.integrations.find_by(id: params[:integration_id])
    end

    def integration_type
      @integration_type ||= integration.provider_key
    end

    def category
      @category ||= ::IntegrationCustomers::BaseCustomer.category_for(customer_type)
    end

    def customer_type
      @customer_type ||= ::IntegrationCustomers::BaseCustomer.customer_type(integration_type)
    rescue NotImplementedError
      nil
    end

    def sync_with_provider
      @sync_with_provider ||= ActiveModel::Type::Boolean.new.cast(params[:sync_with_provider])
    end

    def create_integration_customer?
      sync_with_provider || params[:external_customer_id].present?
    end

    def integration_customer_params
      @integration_customer_params ||= params
        .slice(:external_customer_id, :subsidiary_id, :sync_with_provider, :targeted_object)
        .merge(integration_type:, integration_code: integration.code)
    end

    def create_integration_customer
      ::IntegrationCustomers::CreateService.call!(
        params: integration_customer_params,
        integration:,
        customer:
      ).integration_customer
    end
  end
end
