# frozen_string_literal: true

module Events
  class CreateService < BaseService
    def validate_params(organization:, params:)
      Events::ValidateCreationService.call(
        organization:,
        params:,
        customer: customer(organization:, params:),
        result:,
        send_webhook: false,
      )
      result
    end

    def call(organization:, params:, timestamp:, metadata:)
      customer = customer(organization:, params:)
      Events::ValidateCreationService.call(organization:, params:, customer:, result:)
      return result unless result.success?

      event_timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_i : timestamp)
      subscription = Subscription
        .where(external_id: params[:external_subscription_id])
        .where('started_at <= ?', event_timestamp)
        .order(started_at: :desc)
        .first || customer&.active_subscriptions&.first

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
        event.timestamp = event_timestamp

        event.save!

        result.event = event
        handle_persisted_event if should_handle_persisted_event?
      end

      Fees::CreateInstantJob.perform_later(charge:, event:) if instant_charge?

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

    private

    delegate :event, to: :result

    def customer(organization:, params:)
      return @customer if defined? @customer

      @customer = if params[:external_subscription_id]
        organization.subscriptions.find_by(external_id: params[:external_subscription_id])&.customer
      else
        Customer.find_by(external_id: params[:external_customer_id], organization_id: organization.id)
      end
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

    def charge
      @charge ||= event.subscription
        .plan
        .charges
        .joins(:billable_metric)
        .find_by(billable_metric: { code: event.code })
    end

    def instant_charge?
      charge&.instant? || false
    end
  end
end
