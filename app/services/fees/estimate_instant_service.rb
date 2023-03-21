# frozen_string_literal: true

module Fees
  class EstimateInstantService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      Events::ValidateCreationService.call(organization:, params:, customer:, result:)
      return result unless result.success?

      if charges.none?
        return result.single_validation_failure!(field: :code, error_code: 'does_not_match_an_instant_charge')
      end

      fees = []

      ActiveRecord::Base.transaction do
        event.save!
        charges.each { |charge| fees += estimated_charge_fees(charge) }

        # NOTE: make sure the event is not persisted in database
        raise ActiveRecord::Rollback
      end

      fees.each { |f| f.instant_event_id = nil }

      result.fees = fees
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :organization, :params

    def event
      return @event if @event

      @event = organization.events.new(
        code: params[:code],
        customer:,
        subscription:,
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

    def subscription
      organization
        .subscriptions
        .active
        .where(external_id: params[:external_subscription_id])
        .where('started_at <= ?', Time.current)
        .order(started_at: :desc)
        .first || customer&.active_subscriptions&.first
    end

    def charges
      @charges ||= event.subscription
        .plan
        .charges
        .instant
        .joins(:billable_metric)
        .where(billable_metric: { code: event.code })
    end

    def estimated_charge_fees(charge)
      service_result = Fees::CreateInstantService.call(charge:, event:, estimate: true)
      service_result.raise_if_error!

      service_result.fees
    end
  end
end
