# frozen_string_literal: true

module Events
  class CreateService < BaseService
    def validate_params(organization:, params:)
      customer = customer(organization:, params:)
      timestamp = Time.zone.at((params[:timestamp] || Time.current).to_i)
      subscriptions = subscriptions(organization:, customer:, params:, timestamp:)

      Events::ValidateCreationService.call(
        organization:,
        params:,
        customer:,
        subscriptions:,
        result:,
        send_webhook: false,
      )
      result
    end

    def call(organization:, params:, timestamp:, metadata:)
      customer = customer(organization:, params:)
      event_timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_i : timestamp)
      subscriptions = subscriptions(organization:, customer:, params:, timestamp: event_timestamp)

      Events::ValidateCreationService.call(organization:, params:, customer:, subscriptions:, result:)
      return result unless result.success?

      ActiveRecord::Base.transaction do
        event = organization.events.new
        event.code = params[:code]
        event.transaction_id = params[:transaction_id]
        event.customer = customer
        event.subscription_id = subscriptions.first.id
        event.properties = params[:properties] || {}
        event.metadata = metadata || {}
        event.timestamp = event_timestamp

        event.save!

        result.event = event
        handle_persisted_event if should_handle_persisted_event?
      end

      if non_invoiceable_charges.any?
        non_invoiceable_charges.each { |c| Fees::CreatePayInAdvanceJob.perform_later(charge: c, event:) }
      end

      if invoiceable_charges.any? && applicable_event?
        invoiceable_charges.each do |c|
          Invoices::CreatePayInAdvanceChargeJob.perform_later(charge: c, event:, timestamp: event_timestamp)
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      delivor_error_webhook(organization:, params:, message: e.record.errors.messages)

      # NOTE: Raise error only when validation errors are not transaction_id related
      result.record_validation_failure!(record: e.record) unless e.record.errors.messages.keys == %i[transaction_id]

      result
    rescue ActiveRecord::RecordNotUnique
      delivor_error_webhook(organization:, params:, message: 'transaction_id already exists')

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

    def subscriptions(organization:, customer:, params:, timestamp:)
      return @subscriptions if defined? @subscriptions

      subscriptions = if customer && params[:external_subscription_id].blank?
        customer.subscriptions
      else
        organization.subscriptions.where(external_id: params[:external_subscription_id])
      end
      return unless subscriptions

      @subscriptions = subscriptions
        .where("date_trunc('second', started_at::timestamp) <= ?", timestamp)
        .where("terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?", timestamp)
        .order(started_at: :desc)
      @subscriptions
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

    def charges
      event.subscription
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: { code: event.code })
    end

    def non_invoiceable_charges
      @non_invoiceable_charges ||= charges.where(invoiceable: false)
    end

    def invoiceable_charges
      @invoiceable_charges ||= charges.where(invoiceable: true)
    end

    def applicable_event?
      return false if !billable_metric.count_agg? && event.properties[billable_metric.field_name].nil?
      return false if billable_metric.sum_agg? && event.properties[billable_metric.field_name]&.to_i&.negative?

      true
    end

    def billable_metric
      @billable_metric ||= event.organization.billable_metrics.find_by(code: event.code)
    end

    def delivor_error_webhook(organization:, params:, message:)
      return unless organization.webhook_endpoints.any?

      SendWebhookJob.perform_later(
        'event.error',
        { input_params: params, error: message, organization_id: organization.id, status: 422 },
      )
    end
  end
end
