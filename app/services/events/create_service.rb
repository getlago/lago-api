# frozen_string_literal: true

module Events
  class CreateService < BaseService
    def initialize(organization:)
      @organization = organization
      super(nil)
    end

    def validate_params(params:)
      customer = customer(params:)
      timestamp = Time.zone.at((params[:timestamp] || Time.current).to_i)
      subscriptions = subscriptions(customer:, params:, timestamp:)

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

    def call(params:, timestamp:, metadata:)
      customer = customer(params:)
      event_timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_f : timestamp)
      subscriptions = subscriptions(customer:, params:, timestamp: event_timestamp)

      Events::ValidateCreationService.call(organization:, params:, customer:, subscriptions:, result:)
      unless result.success?
        # NOTE: Ignore transaction_id validation failure as they are related to duplicated events
        if result.error.is_a?(BaseService::ValidationFailure) && result.error.messages.keys == %i[transaction_id]
          delivor_error_webhook(params:, message: 'transaction_id already exists')
          return BaseService::Result.new
        end

        return result
      end

      ActiveRecord::Base.transaction do
        event = Event.new
        event.organization_id = organization.id
        event.code = params[:code]
        event.transaction_id = params[:transaction_id]
        event.customer_id = customer.id
        event.external_customer_id = customer.external_id
        event.subscription_id = subscriptions.first.id
        event.external_subscription_id = subscriptions.first.external_id
        event.properties = params[:properties] || {}
        event.metadata = metadata || {}
        event.timestamp = event_timestamp

        event.save!

        result.event = event

        expire_cached_charges(subscriptions)

        if should_handle_quantified_event?
          # For unique count if repeated event got ingested, we want to store this event but prevent further processing
          return result unless quantified_event_service.process_event?

          handle_quantified_event
        end
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
      delivor_error_webhook(params:, message: e.record.errors.messages)

      # NOTE: Raise error only when validation errors are not transaction_id related
      result.record_validation_failure!(record: e.record) unless e.record.errors.messages.keys == %i[transaction_id]

      result
    rescue ActiveRecord::RecordNotUnique
      delivor_error_webhook(params:, message: 'transaction_id already exists')

      result
    end

    private

    attr_reader :organization

    delegate :event, to: :result

    def customer(params:)
      return @customer if defined? @customer

      @customer = if params[:external_subscription_id]
        organization.subscriptions.find_by(external_id: params[:external_subscription_id])&.customer
      else
        Customer.find_by(external_id: params[:external_customer_id], organization_id: organization.id)
      end
    end

    def subscriptions(customer:, params:, timestamp:)
      return @subscriptions if defined? @subscriptions

      subscriptions = if customer && params[:external_subscription_id].blank?
        customer.subscriptions
      else
        organization.subscriptions.where(external_id: params[:external_subscription_id])
      end
      return unless subscriptions

      timestamp_without_precision = Time.zone.at(timestamp.to_i)

      @subscriptions = subscriptions
        .where("date_trunc('second', started_at::timestamp) <= ?::timestamp", timestamp_without_precision)
        .where(
          "terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?",
          timestamp_without_precision,
        )
        .order('terminated_at DESC NULLS FIRST, started_at DESC')
      @subscriptions
    end

    def quantified_event_service
      @quantified_event_service ||= QuantifiedEvents::CreateOrUpdateService.new(result.event)
    end

    def should_handle_quantified_event?
      quantified_event_service.matching_billable_metric?
    end

    def handle_quantified_event
      service_result = quantified_event_service.call
      service_result.raise_if_error!

      event.quantified_event = service_result.quantified_event
      event.save!
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

      true
    end

    def billable_metric
      @billable_metric ||= event.organization.billable_metrics.find_by(code: event.code)
    end

    def delivor_error_webhook(params:, message:)
      return unless organization.webhook_endpoints.any?

      SendWebhookJob.perform_later(
        'event.error',
        { input_params: params, error: message, organization_id: organization.id, status: 422 },
      )
    end

    def expire_cached_charges(subscriptions)
      active_subscription = subscriptions.select(&:active?)
      charges = billable_metric.charges
        .joins(:plan)
        .where(plans: { id: active_subscription.map(&:plan_id) })

      charges.each do |charge|
        active_subscription.each do |subscription|
          Subscriptions::ChargeCacheService.new(subscription:, charge:).expire_cache
        end
      end
    end
  end
end
