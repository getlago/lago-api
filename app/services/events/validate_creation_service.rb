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
      return blank_subscription_error if params[:subscription_ids].blank?
      return invalid_customer_error unless customer

      invalid_subscriptions = params[:subscription_ids].select { |arg| !customer_subscription_ids.include?(arg) }
      return invalid_subscription_error if invalid_subscriptions.present?
      return invalid_code_error unless valid_code?
    end

    def validate_create
      return invalid_customer_error unless customer

      if customer_subscription_ids.count > 1
        return blank_subscription_error if params[:subscription_id].blank?
        return invalid_subscription_error unless valid_subscription_id?
      elsif params[:subscription_id]
        return invalid_subscription_error unless valid_subscription_id?
      else
        return blank_subscription_error if customer_subscription_ids.blank?
      end

      return invalid_code_error unless valid_code?
    end

    def valid_subscription_id?
      customer_subscription_ids.include?(params[:subscription_id])
    end

    def valid_code?
      organization.billable_metrics.pluck(:code).include?(params[:code])
    end

    def send_webhook_notice
      return unless organization.webhook_url?

      object = {
        input_params: params,
        error: result.error,
        organization_id: organization.id
      }

      SendWebhookJob.perform_later(:event, object)
    end

    def customer_subscription_ids
      @customer_subscription_ids ||= customer&.active_subscriptions&.pluck(:id)
    end

    def blank_subscription_error
      result.fail!(code: 'missing_argument', message: 'subscription does not exist or is not given')
      send_webhook_notice
    end

    def invalid_subscription_error
      result.fail!(code: 'invalid_argument', message: 'subscription_id is invalid')
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
  end
end
