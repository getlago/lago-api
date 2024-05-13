# frozen_string_literal: true

module Events
  class ValidateCreationService
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, params:, result:, customer:, subscriptions: [])
      @organization = organization
      @params = params
      @result = result
      @customer = customer
      @subscriptions = subscriptions
    end

    def call
      validate_create
    end

    private

    attr_reader :organization, :params, :result, :customer, :subscriptions

    def validate_create
      return invalid_customer_error if params[:external_customer_id] && !customer

      if params[:external_subscription_id].blank? && subscriptions.count(&:active?) > 1
        return missing_subscription_error
      end
      return missing_subscription_error if subscriptions.empty?

      if params[:external_subscription_id] &&
          subscriptions.pluck(:external_id).exclude?(params[:external_subscription_id])
        return missing_subscription_error
      end

      return transaction_id_error unless valid_transaction_id?
      return invalid_code_error unless valid_code?
      return invalid_properties_error unless valid_properties?

      nil
    end

    def valid_transaction_id?
      return false if params[:transaction_id].blank?

      Event.where(
        organization_id: organization.id,
        transaction_id: params[:transaction_id],
        external_subscription_id: subscriptions.first.external_id,
      ).none?
    end

    def valid_code?
      billable_metric.present?
    end

    # This validation checks only field_name value since it is important for aggregation DB query integrity.
    # Other checks are performed later and presented in debugger
    def valid_properties?
      return true unless billable_metric.max_agg? || billable_metric.sum_agg? || billable_metric.latest_agg?

      valid_number?((params[:properties] || {})[billable_metric.field_name.to_sym])
    end

    def valid_number?(value)
      true if value.nil? || Float(value)
    rescue ArgumentError
      false
    end

    def missing_subscription_error
      result.not_found_failure!(resource: 'subscription')
    end

    def transaction_id_error
      result.validation_failure!(errors: {transaction_id: ['value_is_missing_or_already_exists']})
    end

    def invalid_code_error
      result.not_found_failure!(resource: 'billable_metric')
    end

    def invalid_properties_error
      result.validation_failure!(errors: {properties: ['value_is_not_valid_number']})
    end

    def invalid_customer_error
      result.not_found_failure!(resource: 'customer')
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: params[:code])
    end
  end
end
