# frozen_string_literal: true

module Invoices
  class PreviewService < BaseService
    Result = BaseResult[:subscriptions, :invoice, :fees_taxes]

    def initialize(customer:, subscriptions:, applied_coupons: [])
      @customer = customer
      @subscriptions = subscriptions
      @applied_coupons = applied_coupons
      @first_subscription = subscriptions.first
      @persisted_subscriptions = subscriptions.any?(&:persisted?)
      @subscription_context = fetch_context

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "subscription") if subscriptions.empty?
      return result.not_allowed_failure!(code: "premium_integration_missing") if persisted_subscriptions && !organization.preview_enabled?
      return result unless currencies_aligned?
      return result unless billing_times_aligned?

      @invoice = Invoice.new(
        organization:,
        billing_entity:,
        customer:,
        invoice_type: :subscription,
        currency: first_subscription.plan.amount_currency,
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
      add_charge_fees
      compute_tax_and_totals

      result.invoice = invoice
      result.subscriptions = subscriptions
      result
    end

    private

    attr_accessor :customer, :subscriptions, :invoice, :applied_coupons, :first_subscription, :persisted_subscriptions, :subscription_context
    delegate :organization, to: :customer
    delegate :billing_entity, to: :customer

    def fetch_context
      return :terminated if subscriptions.any?(&:terminated?)

      :default
    end

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

    def billing_times_aligned?
      return true if subscriptions.size == 1

      if end_of_periods.map { |e| e.to_date.to_s }.uniq.count > 1
        result.single_validation_failure!(error_code: "billing_periods_does_not_match")
        return false
      end

      true
    end

    def end_of_periods
      @end_of_periods ||= subscriptions.map do |subscription|
        Subscriptions::DatesService
          .new_instance(subscription, Time.current, current_usage: true)
          .end_of_period
      end
    end

    def boundaries(subscription)
      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        billing_time,
        current_usage: subscription.persisted? && subscription.terminated? && subscription.upgraded?
      )

      boundaries = BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        timestamp: billing_time,
        charges_duration: date_service.charges_duration_in_days
      )

      subscription.adjusted_boundaries(billing_time, boundaries)
    end

    def billing_time
      return @billing_time if defined? @billing_time

      @billing_time = if subscription_context == :terminated
        first_subscription.terminated_at
      elsif persisted_subscriptions
        end_of_periods.first + 1.day
      elsif first_subscription.plan.pay_in_advance?
        first_subscription.subscription_at
      else
        ds = Subscriptions::DatesService.new_instance(first_subscription, first_subscription.subscription_at, current_usage: true)
        ds.end_of_period + 1.day
      end
    end

    def issuing_date
      return @issuing_date if defined?(@issuing_date)

      date = billing_time.in_time_zone(customer.applicable_timezone).to_date
      @issuing_date = date + customer.applicable_invoice_grace_period.days
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end

    def add_subscription_fees
      invoice.fees = subscriptions
        .filter { |subscription| should_create_subscription_fee?(subscription) }
        .map do |subscription|
        Fees::SubscriptionService.call!(
          invoice:,
          subscription:,
          boundaries: boundaries(subscription),
          context: :preview
        ).fee
      end
    end

    def add_charge_fees
      subscriptions.select(&:persisted?).map do |subscription|
        boundaries = boundaries(subscription)

        charges = []
        subscription.plan.charges.joins(:billable_metric)
          .includes(:taxes, billable_metric: :organization, filters: {values: :billable_metric_filter})
          .where(invoiceable: true)
          .where
          .not(pay_in_advance: true, billable_metric: {recurring: false}).find_each do |c|
          next if should_not_create_charge_fee?(c, subscription)
          charges << c
        end

        context = OpenTelemetry::Context.current

        invoice.fees << Parallel.flat_map(charges, in_threads: ENV["LAGO_PARALLEL_THREADS_COUNT"]&.to_i || 0) do |charge|
          OpenTelemetry::Context.with_current(context) do
            ActiveRecord::Base.connection_pool.with_connection do
              cache_middleware = Subscriptions::ChargeCacheMiddleware.new(
                subscription:,
                charge:,
                to_datetime: boundaries.charges_to_datetime
              )

              Fees::ChargeService
                .call!(invoice:, charge:, subscription:, boundaries:, context: :invoice_preview, cache_middleware:)
                .fees
            end
          end
        end
      end
    end

    def compute_tax_and_totals
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

      if invoice.fees_amount_cents&.positive? && applied_coupons.present?
        Coupons::PreviewService.call(invoice:, applied_coupons:)
      end

      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents - invoice.coupons_amount_cents

      if provider_taxation? && invoice.fees.any?
        apply_provider_taxes
      elsif invoice.fees.any?
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
      terminated_subscription = subscriptions.none?(&:downgraded?) ? subscriptions.find(&:terminated?) : nil
      credits = Preview::CreditsService.call!(invoice:, terminated_subscription:).credits

      invoice.credits << credits
      invoice.total_amount_cents -= credits.sum(&:amount_cents)
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
    rescue BaseService::ThrottlingError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
      apply_zero_tax
    end

    def apply_zero_tax
      invoice.taxes_amount_cents = 0
      invoice.taxes_rate = 0
    end

    def provider_taxation?
      customer.integration_customers.find { |ic| ic.tax_kind? }
    end

    def should_create_subscription_fee?(subscription)
      return true if subscription_context == :default

      subscription.terminated? == subscription.plan.pay_in_arrears?
    end

    def should_not_create_charge_fee?(charge, subscription)
      return false if subscription_context == :default

      if charge.pay_in_advance?
        condition = charge.billable_metric.recurring? &&
          subscription.terminated? &&
          (subscription.upgraded? || subscription.next_subscription.nil?)

        return condition
      end

      return false if charge.prorated?

      charge.billable_metric.recurring? &&
        subscription.terminated? &&
        subscription.upgraded? &&
        charge.included_in_next_subscription?(subscription)
    end
  end
end
