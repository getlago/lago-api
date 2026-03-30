# frozen_string_literal: true

module Invoices
  class RateSchedulesBillingService < BaseService
    Result = BaseResult[:invoice]

    def initialize(subscription_rate_schedules:, timestamp:)
      @subscription_rate_schedules = subscription_rate_schedules
      @timestamp = timestamp
      @customer = subscription_rate_schedules.first.subscription.customer
      @currency = subscription_rate_schedules.first.rate_schedule.amount_currency

      super
    end

    def call
      ActiveRecord::Base.transaction do
        create_generating_invoice
        result.invoice = invoice

        create_invoice_subscriptions
        create_fees

        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

        # TODO: Apply commitments, discounts, coupons
        # TODO: Compute taxes and totals

        set_invoice_status
        invoice.save!
      end

      # TODO: Send webhooks, trigger payments, etc.

      result
    end

    private

    attr_reader :subscription_rate_schedules, :timestamp, :customer, :currency

    attr_accessor :invoice

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :subscription,
        invoicing_reason: :subscription_periodic,
        currency:,
        datetime: Time.zone.at(timestamp)
      )
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def create_invoice_subscriptions
      subscription_rate_schedules.group_by(&:subscription_id).each_value do |srs_group|
        subscription = srs_group.first.subscription

        InvoiceSubscription.create!(
          organization: subscription.organization,
          invoice:,
          subscription:,
          timestamp: Time.zone.at(timestamp),
          recurring: true,
          invoicing_reason: :subscription_periodic
        )
      end
    end

    def create_fees
      subscription_rate_schedules.each do |srs|
        create_fee(srs) # Must run before update_next_billing_date! — fee_properties reads current boundaries
        srs.update_next_billing_date!(billed: true)
      end
    end

    def create_fee(srs)
      rs = srs.rate_schedule
      pi = srs.product_item

      amount_cents, units = compute_amount_and_units(srs)
      precise_amount_cents = amount_cents.to_d

      Fee.create!(
        invoice:,
        organization_id: invoice.organization_id,
        billing_entity_id: invoice.billing_entity_id,
        subscription: srs.subscription,
        subscription_rate_schedule: srs,
        amount_cents:,
        precise_amount_cents:,
        amount_currency: rs.amount_currency,
        fee_type: :product_item,
        invoiceable_type: "ProductItem",
        invoiceable: pi,
        units:,
        properties: fee_properties(srs),
        payment_status: :pending,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        unit_amount_cents: units.zero? ? 0 : (amount_cents / units).round,
        precise_unit_amount: units.zero? ? 0.0 : (precise_amount_cents / units).to_f,
        invoice_display_name: rs.invoice_display_name
      )
    end

    def compute_amount_and_units(srs)
      rs = srs.rate_schedule
      pi = srs.product_item

      case pi.item_type
      when "fixed"
        units = rs.units || BigDecimal("1")
        amount = (rs.properties["amount"].to_d * units * currency_subunit).round
        [amount, units]
      when "subscription"
        amount = (rs.properties["amount"].to_d * currency_subunit).round
        [amount, BigDecimal("1")]
      when "usage"
        # TODO: Aggregation + charge model pipeline (reuses v1 layers via Chargeable interface)
        [0, BigDecimal("0")]
      else
        raise "Unknown item_type: #{pi.item_type}"
      end
    end

    def fee_properties(srs)
      {
        from_datetime: srs.current_period_started_at&.iso8601,
        to_datetime: srs.next_billing_date&.iso8601
      }
    end

    def currency_subunit
      @currency_subunit ||= Money::Currency.new(currency).subunit_to_unit.to_d
    end

    def set_invoice_status
      if grace_period?
        invoice.status = :draft
      else
        Invoices::TransitionToFinalStatusService.call(invoice:)
      end
    end

    def grace_period?
      @grace_period ||= customer.applicable_invoice_grace_period.positive?
    end
  end
end
