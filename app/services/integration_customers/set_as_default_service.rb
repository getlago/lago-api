# frozen_string_literal: true

module IntegrationCustomers
  class SetAsDefaultService < ::BaseService
    Result = BaseResult[:integration_customer]

    def initialize(integration_customer:)
      @integration_customer = integration_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "integration_customer") unless integration_customer

      if integration_customer.is_default?
        result.integration_customer = integration_customer
        return result
      end

      ActiveRecord::Base.transaction do
        Customers::LockService.call(customer: integration_customer.customer, scope: :integration_customer) do
          integration_customer.customer.integration_customers
            .where(category: integration_customer.category)
            .where.not(id: integration_customer.id)
            .update!(is_default: false)
          integration_customer.update!(is_default: true)
        end
      end

      result.integration_customer = integration_customer

      result
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :integration_customer
  end
end
