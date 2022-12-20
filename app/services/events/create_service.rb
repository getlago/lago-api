# frozen_string_literal: true

module Events
  class CreateService < BaseService
    ALL_REQUIRED_PARAMS = %i[transaction_id code].freeze
    ONE_REQUIRED_PARAMS = %i[external_subscription_id external_customer_id].freeze

    def validate_params(params:)
      params_errors = ALL_REQUIRED_PARAMS.each_with_object({}) do |key, errors|
        errors[key] = ['value_is_mandatory'] if params[key].blank?
      end
      params_errors[:base] = ['missing_external_identifier'] if ONE_REQUIRED_PARAMS.all? { |key| params[key].blank? }

      # NOTE: In case of multiple subscriptions, we return an error if subscription_id is not given.
      if params[:external_customer_id].present? && params[:external_subscription_id].blank?
        customer = Customer.find_by(external_id: params[:external_customer_id])
        subscriptions_count = customer ? customer.active_subscriptions.count : 0
        params_errors[:external_subscription_id] = ['value_is_mandatory'] if subscriptions_count > 1
      end

      return result if params_errors.blank?

      result.validation_failure!(errors: params_errors)
    end

    def call(organization:, params:, timestamp:, metadata:)
      customer = if params[:external_subscription_id]
        organization.subscriptions.find_by(external_id: params[:external_subscription_id])&.customer
      else
        Customer.find_by(external_id: params[:external_customer_id], organization_id: organization.id)
      end

      Events::ValidateCreationService.call(
        organization: organization,
        params: params,
        customer: customer,
        result: result,
      )
      return result unless result.success?

      subscription = Subscription.find_by(external_id: params[:external_subscription_id]) || customer&.active_subscriptions&.first

      ActiveRecord::Base.transaction do
        event = organization.events.find_by(transaction_id: params[:transaction_id], subscription_id: subscription.id)

        if event
          result.event = event
          return result
        end

        event = organization.events.new
        event.code = params[:code]
        event.transaction_id = params[:transaction_id]
        event.customer = customer
        event.subscription_id = subscription.id
        event.properties = params[:properties] || {}
        event.metadata = metadata || {}

        event.timestamp = Time.zone.at(params[:timestamp]) if params[:timestamp]
        event.timestamp ||= timestamp

        event.save!

        result.event = event
        handle_persisted_event if should_handle_persisted_event?
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)

      if organization.webhook_url?
        SendWebhookJob.perform_later(
          :event,
          { input_params: params, error: result.error.message, organization_id: organization.id },
        )
      end

      result
    end

    def persisted_event_service
      @persisted_event_service ||= PersistedEvents::CreateOrUpdateService.new(result.event)
    end

    def should_handle_persisted_event?
      persisted_event_service.matching_billable_metric?
    end

    def handle_persisted_event
      service_result = persisted_event_service.call
      service_result.raise_if_error!
    end
  end
end
