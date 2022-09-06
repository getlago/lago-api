# frozen_string_literal: true

module PersistedEvents
  class ValidateCreationService
    def self.call(...)
      new(...).call
    end

    def initialize(subscription:, billable_metric:, params:)
      @subscription = subscription
      @billable_metric = billable_metric
      @params = params&.with_indifferent_access
    end

    def call
      return 'invalid_operation_type' unless valid_operation_type?
      return 'recurring_resource_already_added' unless valid_addition?
      return 'recurring_resource_not_found' unless valid_removal?

      nil
    end

    private

    attr_accessor :subscription, :billable_metric, :params

    delegate :customer, to: :subscription

    def operation_type
      @operation_type ||= params.dig('properties', 'operation_type')&.to_sym
    end

    def external_id
      @external_id ||= params.dig('properties', billable_metric.field_name)
    end

    def valid_operation_type?
      %i[add remove].include?(operation_type)
    end

    def valid_addition?
      return true unless operation_type == :add

      # NOTE: Ensure no active persisted metric exists with the same external id
      PersistedEvent.where(
        customer_id: customer.id,
        external_id: external_id,
        external_subscription_id: subscription.external_id,
      ).where(removed_at: nil).none?
    end

    def valid_removal?
      return true unless operation_type == :remove

      PersistedEvent.where(
        customer_id: customer.id,
        external_id: external_id,
        external_subscription_id: subscription.external_id,
      ).where(removed_at: nil).exists?
    end
  end
end
