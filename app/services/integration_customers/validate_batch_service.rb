# frozen_string_literal: true

module IntegrationCustomers
  # Checks the input of CreateOrUpdateBatchService, which runs after the customer is saved.
  class ValidateBatchService < ::BaseService
    Result = BaseResult

    def initialize(integration_customers:)
      @integration_customers = integration_customers&.map { |c| c.to_h.deep_symbolize_keys }
      super
    end

    def call
      if integration_customers&.any? { !IntegrationCustomers::BaseCustomer::CUSTOMER_TYPES.key?(it[:integration_type]) }
        result.single_validation_failure!(field: :integration_type, error_code: "value_is_invalid")
      else
        result
      end
    end

    private

    attr_reader :integration_customers
  end
end
