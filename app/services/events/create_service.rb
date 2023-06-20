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
        handle_quantified_event if should_handle_quantified_event?
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
      result.record_validation_failure!(record: e.record)

      if organization.webhook_url?
        SendWebhookJob.perform_later(
          'event.error',
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
  end
end
