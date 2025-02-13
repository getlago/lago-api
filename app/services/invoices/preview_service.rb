# frozen_string_literal: true

module Invoices
  class PreviewService < BaseService
    Result = BaseResult[:subscriptions, :invoice, :fees_taxes]

    def initialize(customer:, subscriptions:, applied_coupons: [])
      @customer = customer
      @subscriptions = subscriptions
      @applied_coupons = applied_coupons

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "subscription") if subscriptions.empty?
      return result unless currencies_aligned?

      @invoice = Invoice.new(
        organization: customer.organization,
        customer:,
        invoice_type: :subscription,
        currency: subscriptions.first.plan.amount_currency,
        timezone: customer.applicable_timezone,
        issuing_date:,
        payment_due_date:,
        net_payment_term: customer.applicable_net_payment_term,
        created_at: Time.current,
        updated_at: Time.current
      )
      invoice.credits = []
      invoice.subscriptions = subscriptions

      add_subscription_fees
      compute_tax_and_totals

      result.invoice = invoice
      result.subscriptions = subscriptions
      result
    end

    private

    attr_accessor :customer, :subscriptions, :invoice, :applied_coupons

    def currencies_aligned?
      subscription_currencies = subscriptions.filter_map { |s| s.plan&.amount_currency }

      if subscription_currencies.uniq.count > 1
        result.single_validation_failure!(error_code: "subscription_currencies_does_not_match")
        return false
      end

      if customer.currency && customer.currency != subscription_currencies.first
        result.single_validation_failure!(error_code: "customer_currency_does_not_match")
        return false
      end

      true
    end

    def billing_time
      return @billing_time if defined? @billing_time

      subscription = subscriptions.first

      return subscription.subscription_at if subscription.plan.pay_in_advance?

      ds = Subscriptions::DatesService.new_instance(subscription, subscription.subscription_at, current_usage: true)

      @billing_time = ds.end_of_period + 1.day
    end

    def issuing_date
      billing_time.in_time_zone(customer.applicable_timezone).to_date
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end

    def add_subscription_fees
      invoice.fees = subscriptions.map do |subscription|
        date_service = Subscriptions::DatesService.new_instance(subscription, billing_time)

        boundaries = {
          from_datetime: date_service.from_datetime,
          to_datetime: date_service.to_datetime,
          charges_from_datetime: date_service.charges_from_datetime,
          charges_to_datetime: date_service.charges_to_datetime,
          timestamp: billing_time
        }

        fee = Fees::SubscriptionService.call(
          invoice:,
          subscription:,
          boundaries:,
          context: :preview
        ).raise_if_error!.fee

        subscription.fees = [fee]

        fee
      end
    end

    def compute_tax_and_totals
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

      if invoice.fees_amount_cents&.positive? && applied_coupons.present?
        Coupons::PreviewService.call(invoice:, applied_coupons:)
      end

      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents - invoice.coupons_amount_cents

      if provider_taxation?
        apply_provider_taxes
      else
        apply_taxes
      end

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

    def apply_taxes
      invoice.fees.each do |fee|
        taxes_result = Fees::ApplyTaxesService.call(fee:)
        taxes_result.raise_if_error!
      end

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!
    end

    def apply_provider_taxes
      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:, fees: invoice.fees)

      if taxes_result.success?
        result.fees_taxes = taxes_result.fees
        invoice.fees.each do |fee|
          fee_taxes = result.fees_taxes.find { |item| item.item_key == fee.item_key }

          res = Fees::ApplyProviderTaxesService.call(fee:, fee_taxes:)
          res.raise_if_error!
        end

        res = Invoices::ApplyProviderTaxesService.call(invoice:, provider_taxes: result.fees_taxes)
        res.raise_if_error!
      else
        apply_zero_tax
      end
    rescue BaseService::ThrottlingError
      apply_zero_tax
    end

    def apply_zero_tax
      invoice.taxes_amount_cents = 0
      invoice.taxes_rate = 0
    end

    def provider_taxation?
      customer.integration_customers.find { |ic| ic.type == "IntegrationCustomers::AnrokCustomer" }
    end
  end
end
