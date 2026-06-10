# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class BillFixedChargesDeltaService < BaseService
      Result = BaseResult

      def initialize(subscription:, invoice:)
        @subscription = subscription
        @invoice = invoice
        super
      end

      def call
        return result unless subscription.fixed_charges.pay_in_advance.any?

        timestamps = delta_event_timestamps
        return result if timestamps.empty?

        timestamps.each do |timestamp|
          Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(subscription, timestamp.to_i)
        end

        result
      end

      private

      attr_reader :subscription, :invoice

      def delta_event_timestamps
        creation_timestamp = subscription.started_at + 1.second

        subscription.fixed_charge_events
          .where(fixed_charge: subscription.fixed_charges.pay_in_advance)
          .where("fixed_charge_events.timestamp > ? AND fixed_charge_events.timestamp <= ?", creation_timestamp, Time.current)
          .distinct
          .pluck(:timestamp)
      end
    end
  end
end
