# frozen_string_literal: true

module Invoices
  class CreateService < BaseService
    def initialize(subscriptions:, timestamp:)
      @subscriptions = subscriptions
      @timestamp = timestamp
      @customer = subscriptions&.first&.customer
      @currency = subscriptions&.first&.plan&.amount_currency

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          customer: customer,
          issuing_date: Time.zone.at(timestamp).to_date,
          invoice_type: :subscription,

          amount_currency: currency,
          vat_amount_currency: currency,
          credit_amount_currency: currency,
          total_amount_currency: currency,

          # NOTE: Apply credits before VAT, will be changed with credit note feature
          legacy: true,
          vat_rate: customer.applicable_vat_rate,
        )

        subscriptions.each do |subscription|
          boundaries = calculate_boundaries(subscription)

          create_subscription_fee(invoice, subscription, boundaries) if should_create_subscription_fee?(subscription)
          create_charges_fees(invoice, subscription, boundaries) if should_create_charge_fees?(invoice, subscription)
        end

        compute_amounts(invoice)

        create_credit_note_credit(invoice) if should_create_credit_note_credit?
        create_coupon_credit(invoice) if should_create_coupon_credit?
        create_applied_prepaid_credit(invoice) if should_create_applied_prepaid_credit?(invoice)

        invoice.status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.save!

        subscriptions.each { |subscription| invoice.subscriptions << subscription }

        result.invoice = invoice
      end

      SendWebhookJob.perform_later(:invoice, result.invoice) if should_deliver_webhook?
      create_payment(result.invoice)
      track_invoice_created(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :subscriptions, :timestamp, :customer, :currency

    def date_service(subscription)
      Subscriptions::DatesService.new_instance(
        subscription,
        Time.zone.at(timestamp).to_date,
        current_usage: subscription.terminated? && subscription.upgraded?,
      )
    end

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)

      invoice.credit_amount_cents = 0

      invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
    end

    def create_subscription_fee(invoice, subscription, boundaries)
      fee_result = Fees::SubscriptionService
        .new(invoice: invoice, subscription: subscription, boundaries: boundaries).create
      fee_result.throw_error unless fee_result.success?
    end

    def create_charges_fees(invoice, subscription, boundaries)
      subscription.plan.charges.each do |charge|
        fee_result = Fees::ChargeService
          .new(invoice: invoice, charge: charge, subscription: subscription, boundaries: boundaries).create
        fee_result.throw_error unless fee_result.success?
      end
    end

    def should_create_subscription_fee?(subscription)
      # NOTE: When plan is pay in advance we generate an invoice upon subscription creation
      # We want to prevent creating subscription fee if subscription creation already happened on billing day
      return false if subscription.plan.pay_in_advance? && subscription.fee_exists?(Time.zone.at(timestamp).to_date)

      return false unless should_create_yearly_subscription_fee?(subscription)

      # NOTE: When a subscription is terminated we still need to charge the subscription
      #       fee if the plan is in pay in arrear, otherwise this fee will never
      #       be created.
      subscription.active? || (subscription.terminated? && subscription.plan.pay_in_arrear?)
    end

    def should_create_yearly_subscription_fee?(subscription)
      return true unless subscription.plan.yearly?

      # NOTE: we do not want to create a subscription fee for plans with bill_charges_monthly activated
      # But we want to keep the subscription charge when it has to proceed
      # Cases when we want to charge a subscription:
      # - Plan is pay in advance, we're at the beginning of the period or subscription has never been billed
      # - Plan is pay in arrear and we're at the beginning of the period
      date_service(subscription).first_month_in_yearly_period? ||
        subscription.plan.pay_in_advance && !subscription.already_billed?
    end

    def should_create_charge_fees?(invoice, subscription)
      # We should take a look at charges if subscription is created in the past and if it is not upgrade
      if subscription.plan.pay_in_advance? && subscription.started_in_past? && subscription.previous_subscription.nil?
        return true
      end

      # NOTE: Charges should not be billed in advance when we are just upgrading to a new
      #       pay_in_advance subscription
      return false if subscription.plan.pay_in_advance? && subscription.invoices.where.not(id: invoice.id).count.zero?

      true
    end

    def should_deliver_webhook?
      customer.organization.webhook_url?
    end

    def applied_coupon
      return @applied_coupon if @applied_coupon

      @applied_coupon = customer.applied_coupons.active.first
    end

    def credit_notes
      @credit_notes ||= customer.credit_notes.available.order(created_at: :asc)
    end

    def wallet
      return @wallet if @wallet

      @wallet = customer.wallets.active.first
    end

    def should_create_credit_note_credit?
      credit_notes.any?
    end

    def should_create_coupon_credit?
      return false if applied_coupon.nil?

      return applied_coupon.amount_currency == currency if applied_coupon.coupon.fixed_amount?

      true
    end

    def should_create_applied_prepaid_credit?(invoice)
      return false unless wallet&.active?
      return false unless invoice.total_amount_cents&.positive?

      wallet.balance.positive?
    end

    def create_credit_note_credit(invoice)
      credit_result = Credits::CreditNoteService.new(
        invoice: invoice,
        credit_notes: credit_notes,
      ).call
      credit_result.throw_error unless credit_result.success?

      refresh_amounts(invoice: invoice, credit_amount_cents: credit_result.credits.sum(&:amount_cents))
    end

    def create_coupon_credit(invoice)
      credit_result = Credits::AppliedCouponService.new(
        invoice: invoice,
        applied_coupon: applied_coupon,
      ).create
      credit_result.throw_error unless credit_result.success?

      refresh_amounts(invoice: invoice, credit_amount_cents: credit_result.credit.amount_cents)
    end

    def create_applied_prepaid_credit(invoice)
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.new(invoice: invoice, wallet: wallet).create
      prepaid_credit_result.throw_error unless prepaid_credit_result.success?

      refresh_amounts(invoice: invoice, credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
    end

    # NOTE: Since credit impact the invoice total amount, we need to recompute it
    def refresh_amounts(invoice:, credit_amount_cents:)
      invoice.credit_amount_cents += credit_amount_cents
      invoice.total_amount_cents -= credit_amount_cents
    end

    def create_payment(invoice)
      case customer.payment_provider&.to_sym
      when :stripe
        Invoices::Payments::StripeCreateJob.perform_later(invoice)
      end
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type,
        },
      )
    end

    def calculate_boundaries(subscription)
      date_service = date_service(subscription)

      {
        from_date: date_service.from_date,
        to_date: date_service.to_date,
        charges_from_date: date_service.charges_from_date,
        charges_to_date: date_service.charges_to_date,
        timestamp: timestamp,
      }
    end
  end
end
