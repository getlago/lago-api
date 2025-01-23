# frozen_string_literal: true

module Invoices
  class PreviewService < BaseService
    def initialize(customer:, subscription:, applied_coupons: [])
      @customer = customer
      @subscription = subscription
      @applied_coupons = applied_coupons

      super
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'subscription') unless subscription

      @invoice = Invoice.new(
        organization: customer.organization,
        customer:,
        invoice_type: :subscription,
        currency: subscription.plan&.amount_currency,
        timezone: customer.applicable_timezone,
        issuing_date:,
        payment_due_date:,
        net_payment_term: customer.applicable_net_payment_term,
        created_at: Time.current,
        updated_at: Time.current
      )
      invoice.credits = []
      invoice.subscriptions = [subscription]

      add_subscription_fee
      compute_tax_and_totals

      result.invoice = invoice
      result
    end

    private

    attr_accessor :customer, :subscription, :invoice, :applied_coupons

    def boundaries
      {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        timestamp: billing_time
      }
    end

    def date_service
      Subscriptions::DatesService.new_instance(subscription, billing_time)
    end

    def billing_time
      return @billing_time if defined? @billing_time

      ds = Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)

      @billing_time = ds.end_of_period + 1.day
    end

    def issuing_date
      billing_time.in_time_zone(customer.applicable_timezone).to_date
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end

    def add_subscription_fee
      invoice.fees =
        [
          Fees::SubscriptionService.call(
            invoice:,
            subscription:,
            boundaries:,
            context: :preview
          ).raise_if_error!.fee
        ]
    end

    def compute_tax_and_totals
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

      if invoice.fees_amount_cents&.positive? && applied_coupons.present?
        Coupons::PreviewService.call(invoice:, applied_coupons:)
      end

      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents - invoice.coupons_amount_cents

      invoice.fees.each do |fee|
        taxes_result = Fees::ApplyTaxesService.call(fee:)
        taxes_result.raise_if_error!
      end

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!

      invoice.sub_total_including_taxes_amount_cents = (
        invoice.sub_total_excluding_taxes_amount_cents + invoice.taxes_amount_cents
      )

      invoice.total_amount_cents = (
        invoice.sub_total_including_taxes_amount_cents - invoice.credit_notes_amount_cents
      )

      create_credit_note_credits
      create_applied_prepaid_credits
    end

    def create_credit_note_credits
      credit_result = Credits::CreditNoteService.call(invoice:, context: :preview)
      credit_result.raise_if_error!

      invoice.total_amount_cents -= credit_result.credits.sum(&:amount_cents)
    end

    def create_applied_prepaid_credits
      return unless customer.persisted?
      return unless wallet
      return unless invoice.total_amount_cents&.positive?
      return unless wallet.balance.positive?

      amount_cents = if wallet.balance_cents <= invoice.total_amount_cents
        wallet.balance_cents
      else
        invoice.total_amount_cents
      end
      invoice.prepaid_credit_amount_cents += amount_cents
      invoice.total_amount_cents -= amount_cents
    end

    def wallet
      return @wallet if defined? @wallet

      @wallet = customer.wallets.active.first
    end
  end
end
