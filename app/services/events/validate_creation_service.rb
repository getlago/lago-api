# frozen_string_literal: true

module Events
  class ValidateCreationService
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, params:, result:, customer:, batch: false, send_webhook: true)
      @organization = organization
      @params = params
      @result = result
      @customer = customer
      @batch = batch
      @send_webhook = send_webhook
    end

    def call
      batch ? validate_create_batch : validate_create
    end

    private

    attr_reader :organization, :params, :result, :customer, :batch, :send_webhook

    def validate_create_batch
      return missing_subscription_error if params[:external_subscription_ids].blank?
      return invalid_customer_error unless customer

      invalid_subscriptions = params[:external_subscription_ids].reject do |arg|
        customer_external_subscription_ids.include?(arg)
      end
      return missing_subscription_error if invalid_subscriptions.present?
      return invalid_code_error unless valid_code?

      invalid_persisted_events = params[:external_subscription_ids]
        .map { |external_id| organization.subscriptions.find_by(external_id:) }
        .each_with_object({}) do |subscription, errors|
          validation_result = persisted_event_validation(subscription)
          next errors if validation_result.blank?

          validation_result.each do |field, codes|
            errors["subscription[#{subscription.external_id}]_#{field}".to_sym] = codes
          end
          errors
        end
      return invalid_persisted_event_error(invalid_persisted_events) if invalid_persisted_events.present?

      nil
    end

    def validate_create
      return invalid_customer_error unless customer
      return missing_subscription_error unless valid_subscription?
      return invalid_code_error unless valid_code?
      return invalid_properties_error unless valid_properties?

      subscription = organization.subscriptions.find_by(external_id: params[:external_subscription_id])
      invalid_persisted_event = persisted_event_validation(subscription || customer.active_subscriptions.first)
      return invalid_persisted_event_error(invalid_persisted_event) if invalid_persisted_event.present?
    end

    def valid_subscription?
      if customer.active_subscriptions.count > 1
        return false if params[:external_subscription_id].blank? || !valid_subscription_id?
      elsif params[:external_subscription_id]
        return false unless valid_subscription_id?
      elsif customer_external_subscription_ids.blank?
        return false
      end

      true
    end

    def valid_subscription_id?
      customer_external_subscription_ids.include?(params[:external_subscription_id])
    end

    def valid_code?
      billable_metric.present?
    end

    # This validation checks only field_name value since it is important for aggregation DB query integrity.
    # Other checks are performed later and presented in debugger
    def valid_properties?
      return true unless billable_metric.max_agg? || billable_metric.sum_agg?

      valid_number?(params[:properties][billable_metric.field_name.to_sym])
    end

    def valid_number?(value)
      true if value.nil? || Float(value)
    rescue ArgumentError
      false
    end

    def send_webhook_notice
      return unless send_webhook
      return unless organization.webhook_url?

      status = result.error.is_a?(BaseService::NotFoundFailure) ? 404 : 422

      object = {
        input_params: params,
        error: result.error.to_s,
        status:,
        organization_id: organization.id,
      }

      SendWebhookJob.perform_later(:event, object)
    end

    def customer_external_subscription_ids
      @customer_external_subscription_ids ||= customer&.subscriptions&.pluck(:external_id)
    end

    def missing_subscription_error
      result.not_found_failure!(resource: 'subscription')
      send_webhook_notice
    end

    def invalid_code_error
      result.not_found_failure!(resource: 'billable_metric')
      send_webhook_notice
    end

    def invalid_properties_error
      result.validation_failure!(errors: { properties: ['value_is_not_valid_number'] })
      send_webhook_notice
    end

    def invalid_customer_error
      result.not_found_failure!(resource: 'customer')
      send_webhook_notice
    end

    def invalid_persisted_event_error(errors)
      result.validation_failure!(errors:)
      send_webhook_notice
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: params[:code])
    end

    def persisted_event_validation(subscription)
      return {} unless billable_metric.recurring_count_agg?

      validation_service = PersistedEvents::ValidateCreationService.new(
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
