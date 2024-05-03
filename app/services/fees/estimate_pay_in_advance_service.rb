# frozen_string_literal: true

module Fees
  class EstimatePayInAdvanceService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      # NOTE: validation is shared with event creation and is expecting a transaction_id
      @params = params.merge(transaction_id: SecureRandom.uuid)

      super
    end

    def call
      Events::ValidateCreationService.call(organization:, params:, customer:, subscriptions:, result:)
      return result unless result.success?

      if charges.none?
        return result.single_validation_failure!(field: :code, error_code: 'does_not_match_an_instant_charge')
      end

      fees = []

      EventsRecord.transaction do
        event.save!
        charges.each { |charge| fees += estimated_charge_fees(charge) }

        # NOTE: make sure the event is not persisted in database
        raise ActiveRecord::Rollback
      end

      fees.each { |f| f.pay_in_advance_event_id = nil }

      result.fees = fees
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :organization, :params

    def event
      return @event if @event

      @event = Event.new(
        organization_id: organization.id,
        code: params[:code],
        external_customer_id: customer&.external_id,
        external_subscription_id: subscriptions.first&.external_id,
        properties: params[:properties] || {},
        transaction_id: SecureRandom.uuid,
        timestamp: Time.current,
      )
    end

    def customer
      return @customer if @customer

      @customer = if params[:external_subscription_id]
        organization.subscriptions.find_by(external_id: params[:external_subscription_id])&.customer
      else
        Customer.find_by(external_id: params[:external_customer_id], organization_id: organization.id)
      end
    end

    def subscriptions
      return @subscriptions if defined? @subscriptions

      timestamp = Time.current
      subscriptions = if customer && params[:external_subscription_id].blank?
        customer.subscriptions
      else
        organization.subscriptions.where(external_id: params[:external_subscription_id])
      end
      return unless subscriptions

      @subscriptions = subscriptions
        .where("date_trunc('second', started_at::timestamp) <= ?", timestamp)
        .where("terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?", timestamp)
        .order('terminated_at DESC NULLS FIRST, started_at DESC')
    end

    def charges
      @charges ||= subscriptions.first
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: { code: event.code })
    end

    def estimated_charge_fees(charge)
      service_result = Fees::CreatePayInAdvanceService.call(charge:, event:, estimate: true)
      service_result.raise_if_error!

      service_result.fees
    end
  end
end
