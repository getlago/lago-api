# frozen_string_literal: true

module PaymentProviderCustomers
  # Declaratively reconciles a customer's payment provider connections from the GraphQL array:
  # connections absent from the array (matched by id) are discarded, provider connections are
  # created/updated, and the reserved manual connection is created on demand. The customer default
  # is managed through the dedicated set-as-default mutation, not this array.
  class CreateOrUpdateBatchService < BaseService
    Result = BaseResult[:payment_provider_customers]

    MANUAL_CODE = PaymentProviderCustomers::BaseCustomer::MANUAL_CODE

    def initialize(customer:, payment_provider_customers:)
      @customer = customer
      @params_list = payment_provider_customers&.map { |c| c.to_h.deep_symbolize_keys }

      super
    end

    def call
      return result if params_list.nil? || customer.nil?

      # TEMPORARY: the array carries a single connection until multi-connection support ships;
      # reject more than one so the feature is consumed incrementally.
      if params_list.size > 1
        return result.single_validation_failure!(
          field: :payment_provider_customers,
          error_code: "only_one_connection_allowed"
        )
      end

      ActiveRecord::Base.transaction do
        discard_removed_connections
        params_list.each { |params| upsert_connection(params) }
      end

      result.payment_provider_customers = customer.payment_provider_customers.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :customer, :params_list

    def discard_removed_connections
      kept_ids = params_list.filter_map { |params| params[:id] }

      customer.payment_provider_customers.where.not(id: kept_ids).find_each do |connection|
        PaymentProviderCustomers::DestroyService.call!(payment_provider_customer: connection)
      end
    end

    def upsert_connection(params)
      if manual?(params)
        upsert_manual
      elsif params[:id]
        PaymentProviderCustomers::UpdateConnectionService.call!(
          payment_provider_customer: customer.payment_provider_customers.find(params[:id]),
          params: connection_params(params)
        )
      else
        PaymentProviderCustomers::CreateConnectionService.call!(customer:, params: connection_params(params))
      end
    end

    def manual?(params)
      params[:code] == MANUAL_CODE
    end

    def upsert_manual
      return if customer.payment_provider_customers.by_code(MANUAL_CODE).exists?

      customer.payment_provider_customers.create!(
        organization_id: customer.organization_id,
        type: "PaymentProviderCustomers::BaseCustomer",
        code: MANUAL_CODE
      )
    end

    def connection_params(params)
      params.slice(
        :code,
        :payment_provider,
        :payment_provider_code,
        :provider_customer_id,
        :provider_payment_methods,
        :sync_with_provider
      )
    end
  end
end
