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
        resolve_billable_cycles
        return result if billable_pairs.empty?

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

    # NOTE: Resolves (srs, cycle) pairs. For each SRS, find the latest ended
    # cycle that has no fee yet. If none found (race: already billed), skip the SRS.
    def resolve_billable_cycles
      @billable_pairs = subscription_rate_schedules.filter_map do |srs|
        cycle = billable_cycle_for(srs)
        [srs, cycle] if cycle
      end
    end

    attr_reader :billable_pairs

    def billable_cycle_for(srs)
      tz = srs.subscription.customer.applicable_timezone

      srs.cycles
        .where(
          "DATE(subscription_rate_schedule_cycles.to_datetime::timestamptz AT TIME ZONE :tz) " \
          "<= DATE(:billing_at::timestamptz AT TIME ZONE :tz)",
          tz: tz,
          billing_at: Time.zone.at(timestamp)
        )
        .where(
          "NOT EXISTS (SELECT 1 FROM fees " \
          "WHERE fees.subscription_rate_schedule_cycle_id = subscription_rate_schedule_cycles.id " \
          "AND fees.deleted_at IS NULL)"
        )
        .order(cycle_index: :desc)
        .first
    end

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
      billable_pairs.group_by { |srs, _| srs.subscription_id }.each_value do |pairs|
        srs, cycle = pairs.first
        subscription = srs.subscription

        InvoiceSubscription.create!(
          organization: subscription.organization,
          invoice:,
          subscription:,
          timestamp: Time.zone.at(timestamp),
          from_datetime: cycle.from_datetime,
          to_datetime: cycle.to_datetime,
          recurring: true,
          invoicing_reason: :subscription_periodic
        )
      end
    end

    def create_fees
      billable_pairs.each do |srs, cycle|
        create_fee(srs, cycle)
      end
    end

    def create_fee(srs, cycle)
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
        subscription_rate_schedule_cycle: cycle,
        amount_cents:,
        precise_amount_cents:,
        amount_currency: rs.amount_currency,
        fee_type: :product_item,
        invoiceable_type: "ProductItem",
        invoiceable: pi,
        units:,
        properties: fee_properties(cycle),
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
        # TODO: Aggregation + charge model pipeline
        [0, BigDecimal("0")]
      else
        raise "Unknown item_type: #{pi.item_type}"
      end
    end

    def fee_properties(cycle)
      {
        from_datetime: cycle.from_datetime.iso8601,
        to_datetime: cycle.to_datetime.iso8601
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
