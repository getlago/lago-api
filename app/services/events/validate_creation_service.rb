# frozen_string_literal: true

# frozen_string_literal: true

module Events
  class ValidateCreationService
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, params:, result:, customer:, subscriptions: [], batch: false) # rubocop:disable Metrics/ParameterLists
      @organization = organization
      @params = params
      @result = result
      @customer = customer
      @subscriptions = subscriptions
      @batch = batch
    end

    def call
      batch ? validate_create_batch : validate_create
    end

    private

    attr_reader :organization, :params, :result, :customer, :subscriptions, :batch

    def validate_create_batch
      return missing_subscription_error if params[:external_subscription_ids].blank?
      return invalid_customer_error unless customer

      invalid_subscriptions = params[:external_subscription_ids].reject do |arg|
        customer.subscriptions&.pluck(:external_id)&.include?(arg)
      end
      return missing_subscription_error if invalid_subscriptions.present?
      return invalid_code_error unless valid_code?
      return invalid_properties_error unless valid_properties?

      invalid_quantified_events = params[:external_subscription_ids]
        .map { |external_id| organization.subscriptions.find_by(external_id:) }
        .each_with_object({}) do |subscription, errors|
          validation_result = quantified_event_validation(subscription)
          next errors if validation_result.blank?

          validation_result.each do |field, codes|
            errors["subscription[#{subscription.external_id}]_#{field}".to_sym] = codes
          end
          errors
        end
      return invalid_quantified_event_error(invalid_quantified_events) if invalid_quantified_events.present?

      nil
    end

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

      subscription = organization.subscriptions.find_by(external_id: params[:external_subscription_id])
      invalid_quantified_event = quantified_event_validation(subscription || subscriptions.first)
      invalid_quantified_event_error(invalid_quantified_event) if invalid_quantified_event.present?
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
      result.validation_failure!(errors: { transaction_id: ['value_is_missing_or_already_exists'] })
    end

    def invalid_code_error
      result.not_found_failure!(resource: 'billable_metric')
    end

    def invalid_properties_error
      result.validation_failure!(errors: { properties: ['value_is_not_valid_number'] })
    end

    def invalid_customer_error
      result.not_found_failure!(resource: 'customer')
    end

    def invalid_quantified_event_error(errors)
      result.validation_failure!(errors:)
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: params[:code])
    end

    def quantified_event_validation(subscription)
      return {} unless billable_metric.unique_count_agg?

      validation_service = QuantifiedEvents::ValidateCreationService.new(
        result:,
        subscription:,
        billable_metric:,
        args: params,
      )
      return {} if validation_service.valid?

      validation_service.errors
    end
  end
end
