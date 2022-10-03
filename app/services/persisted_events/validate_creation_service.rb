# frozen_string_literal: true

module PersistedEvents
  class ValidateCreationService < BaseValidator
    def initialize(result:, subscription:, billable_metric:, args:)
      @subscription = subscription
      @billable_metric = billable_metric

      super(result, **args.with_indifferent_access)
    end

    def valid?
      validate_operation_type
      validate_addition
      validate_removal

      errors.blank?
    end

    attr_accessor :errors

    private

    attr_accessor :subscription, :billable_metric

    delegate :customer, to: :subscription

    def operation_type
      @operation_type ||= args.dig('properties', 'operation_type')&.to_sym
    end

    def external_id
      @external_id ||= args.dig('properties', billable_metric.field_name)
    end

    def validate_operation_type
      return if %i[add remove].include?(operation_type)

      add_error(field: :operation_type, error_code: 'invalid_operation_type')
    end

    def validate_addition
      return unless operation_type == :add

      # NOTE: Ensure no active persisted metric exists with the same external id
      return if PersistedEvent.where(
        customer_id: customer.id,
        external_id: external_id,
        external_subscription_id: subscription.external_id,
      ).where(removed_at: nil).none?

      add_error(field: billable_metric.field_name, error_code: 'recurring_resource_already_added')
    end

    def validate_removal
      return unless operation_type == :remove

      return if PersistedEvent.where(
        customer_id: customer.id,
        external_id: external_id,
        external_subscription_id: subscription.external_id,
      ).where(removed_at: nil).exists?

      add_error(field: billable_metric.field_name, error_code: 'recurring_resource_not_found')
    end
  end
end
