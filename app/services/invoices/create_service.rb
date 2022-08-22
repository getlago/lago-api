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
        )

        subscriptions.each do |subscription|
          boundaries = calculate_boundaries(subscription)

          create_subscription_fee(invoice, subscription, boundaries) if should_create_subscription_fee?(subscription)
          create_charges_fees(invoice, subscription, boundaries) if should_create_charge_fees?(invoice, subscription)
        end

        compute_amounts(invoice)

        create_credit(invoice) if should_create_credit?

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.total_amount_currency = currency
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
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :subscriptions, :timestamp, :customer, :currency

    def date_service(subscription)
      Subscriptions::DatesService.new_instance(subscription, Time.zone.at(timestamp).to_date)
    end

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = currency
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
      # NOTE: When a subscription is upgraded, the charges will be billed at the end of the period
      #       using the new subscription
      return false if subscription.terminated? && subscription.upgraded?

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

    def should_create_credit?
      return false if applied_coupon.nil?

      applied_coupon.amount_currency == currency
    end

    def create_credit(invoice)
      credit_result = Credits::AppliedCouponService.new(
        invoice: invoice,
        applied_coupon: applied_coupon,
      ).create
      credit_result.throw_error unless credit_result.success?

      # NOTE: Since credit impact the invoice amount we need to recompute the amount
      #       and the VAT amount
      invoice.amount_cents = invoice.amount_cents - credit_result.credit.amount_cents
      invoice.vat_amount_cents = (invoice.amount_cents * customer.applicable_vat_rate).fdiv(100).ceil
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
