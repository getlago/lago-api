# frozen_string_literal: true

module Events
  class CreateBatchService < BaseService
    ALL_REQUIRED_PARAMS = %i[transaction_id code external_subscription_ids].freeze

    def validate_params(params:)
      params_errors = ALL_REQUIRED_PARAMS.each_with_object({}) do |key, errors|
        errors[key] = ['value_is_mandatory'] if params[key].blank?
      end
      return result if params_errors.blank?

      result.validation_failure!(errors: params_errors)
    end

    def call(organization:, params:, timestamp:, metadata:)
      customer = organization.subscriptions.find_by(
        external_id: params[:external_subscription_ids]&.first,
      )&.customer

      Events::ValidateCreationService.call(
        organization: organization,
        params: params,
        customer: customer,
        result: result,
        batch: true,
      )
      return result unless result.success?

      events = []
      ActiveRecord::Base.transaction do
        params[:external_subscription_ids].each do |id|
          subscription = Subscription.find_by(external_id: id)
          event = organization.events.find_by(transaction_id: params[:transaction_id], subscription_id: subscription.id)

          if event
            events << event

            next
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
          handle_persisted_event(event)

          events << event
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)

          if organization.webhook_url?
            SendWebhookJob.perform_later(
              :event,
              { input_params: params, error: result.error, organization_id: organization.id },
            )
          end

          return result
        end
      end

      result.events = events
      result
    end

    def handle_persisted_event(event)
      persisted_service = PersistedEvents::CreateOrUpdateService.new(event)
      return unless persisted_service.matching_billable_metric?

      service_result = persisted_service.call
      service_result.raise_if_error!
    end
  end
end
