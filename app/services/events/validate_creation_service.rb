# frozen_string_literal: true

module Events
  class ValidateCreationService
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, params:, result:, customer:, batch: false)
      @organization = organization
      @params = params
      @result = result
      @customer = customer
      @batch = batch
    end

    def call
      batch ? validate_create_batch : validate_create
    end

    private

    attr_reader :organization, :params, :result, :customer, :batch

    def validate_create_batch
      return blank_subscription_error if params[:external_subscription_ids].blank?
      return invalid_customer_error unless customer

      invalid_subscriptions = params[:external_subscription_ids].select do |arg|
        !customer_external_subscription_ids.include?(arg)
      end
      return invalid_subscription_error if invalid_subscriptions.present?
      return invalid_code_error unless valid_code?

      invalid_persisted_events = params[:external_subscription_ids]
        .map { |external_id| organization.subscriptions.find_by(external_id: external_id) }
        .map { |subscription| [subscription.external_id, persisted_event_validation(subscription)] }
        .reject { |errors| errors.last.blank? }

      if invalid_persisted_events.present?
        return invalid_persisted_event_error(
          invalid_persisted_events.map { |errors| "Subscription #{errors.first}: #{errors.last}" }.join(','),
        )
      end

      nil
    end

    def validate_create
      return invalid_customer_error unless customer

      if customer_external_subscription_ids.count > 1
        return blank_subscription_error if params[:external_subscription_id].blank?
        return invalid_subscription_error unless valid_subscription_id?
      elsif params[:external_subscription_id]
        return invalid_subscription_error unless valid_subscription_id?
      elsif customer_external_subscription_ids.blank?
        return blank_subscription_error
      end

      return invalid_code_error unless valid_code?

      invalid_persisted_event = persisted_event_validation(
        customer.active_subscriptions.first || organization.subscriptions.find_by(id: params[:subscription_id]),
      )
      return invalid_persisted_event_error(invalid_persisted_event) if invalid_persisted_event.present?
    end

    def valid_subscription_id?
      customer_external_subscription_ids.include?(params[:external_subscription_id])
    end

    def valid_code?
      billable_metric.present?
    end

    def send_webhook_notice
      return unless organization.webhook_url?

      object = {
        input_params: params,
        error: result.error,
        organization_id: organization.id,
      }

      SendWebhookJob.perform_later(:event, object)
    end

    def customer_external_subscription_ids
      @customer_external_subscription_ids ||= customer&.active_subscriptions&.pluck(:external_id)
    end

    def blank_subscription_error
      result.fail!(code: 'missing_argument', message: 'subscription does not exist or is not given')
      send_webhook_notice
    end

    def invalid_subscription_error
      result.fail!(code: 'invalid_argument', message: 'external_subscription_id is invalid')
      send_webhook_notice
    end

    def invalid_code_error
      result.fail!(code: 'missing_argument', message: 'code does not exist')
      send_webhook_notice
    end

    def invalid_customer_error
      result.fail!(code: 'missing_argument', message: 'customer cannot be found')
      send_webhook_notice
    end

    def invalid_persisted_event_error(message)
      result.fail!(code: 'invalid_recurring_resource', message: message)
      send_webhook_notice
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: params[:code])
    end

    def persisted_event_validation(subscription)
      return unless billable_metric.recurring_count_agg?

      PersistedEvents::ValidateCreationService.call(
        subscription: subscription,
        billable_metric: billable_metric,
        params: params,
      )
    end
  end
end
