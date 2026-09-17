# frozen_string_literal: true

module DataExports
  module Csv
    class ResolveFeeBillingPeriodService < BaseService
      Result = BaseResult[:from_datetime, :to_datetime]

      def initialize(fee:, invoice_subscription:)
        @fee = fee
        @invoice_subscription = invoice_subscription

        super
      end

      def call
        from_datetime, to_datetime = billing_period

        result.from_datetime = parse_datetime(from_datetime)
        result.to_datetime = parse_datetime(to_datetime)
        result
      end

      private

      attr_reader :fee, :invoice_subscription

      def billing_period
        case fee.fee_type.to_sym
        when :subscription
          properties_period("from_datetime", "to_datetime") || subscription_period
        when :fixed_charge
          properties_period("fixed_charges_from_datetime", "fixed_charges_to_datetime") || fixed_charge_period
        when :commitment
          properties_period("from_datetime", "to_datetime") || commitment_period
        when :charge
          charge_period
        when :add_on
          properties_period("from_datetime", "to_datetime")
        else
          charges_period
        end
      end

      def properties_period(from_key, to_key)
        from_datetime = fee.properties&.dig(from_key)
        to_datetime = fee.properties&.dig(to_key)

        if from_datetime.present? && to_datetime.present?
          [from_datetime, to_datetime]
        end
      end

      def subscription_period
        [invoice_subscription.from_datetime, invoice_subscription.to_datetime]
      end

      def fixed_charge_period
        [invoice_subscription.fixed_charges_from_datetime, invoice_subscription.fixed_charges_to_datetime]
      end

      def commitment_period
        unless invoice_subscription.subscription.plan.pay_in_advance?
          return subscription_period
        end

        previous_invoice_subscription = invoice_subscription.previous_invoice_subscription

        if previous_invoice_subscription
          [previous_invoice_subscription.from_datetime, previous_invoice_subscription.to_datetime]
        else
          [nil, nil]
        end
      end

      def charge_period
        if fee.pay_in_advance?
          properties_period("charges_from_datetime", "charges_to_datetime") || charges_period
        else
          charges_period
        end
      end

      def charges_period
        [invoice_subscription.charges_from_datetime, invoice_subscription.charges_to_datetime]
      end

      def parse_datetime(value)
        if value.is_a?(String)
          Time.zone.parse(value)
        else
          value
        end
      end
    end
  end
end
