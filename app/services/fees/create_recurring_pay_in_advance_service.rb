# frozen_string_literal: true

module Fees
  class CreateRecurringPayInAdvanceService < BaseService
    def initialize(subscriptions:, billing_at:)
      @subscriptions = subscriptions
      @billing_at = billing_at

      super
    end

    def call
      plan_ids = subscriptions.select(&:active?).map(&:plan_id).uniq

      Charge.joins(:billable_metric)
        .where(plan_id: plan_ids, pay_in_advance: true, invoiceable: false)
        .where(billable_metrics: {recurring: true})
        .find_each do |charge|
        last_fee = charge.fees.order(created_at: :desc).first
        event = Event.find_by(id: last_fee&.pay_in_advance_event_id)

        if event
          Fees::CreatePayInAdvanceJob.perform_later(charge:, event:, billing_at:)
        end
      end

      result
    end

    private

    attr_reader :subscriptions, :billing_at
  end
end
