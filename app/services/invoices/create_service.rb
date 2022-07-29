# frozen_string_literal: true

module Invoices
  class CreateService < BaseService
    def initialize(subscription:, timestamp:)
      @subscription = subscription
      @timestamp = timestamp

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.find_or_create_by!(
          customer: subscription.customer,
          from_date: from_date,
          to_date: to_date,
          charges_from_date: charges_from_date,
          issuing_date: issuing_date,
          invoice_type: :subscription,
        )

        create_subscription_fee(invoice) if should_create_subscription_fee?
        create_charges_fees(invoice) if should_create_charge_fees?(invoice)

        compute_amounts(invoice)

        create_credit(invoice) if should_create_credit?

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.total_amount_currency = plan.amount_currency
        invoice.status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.save!
        invoice.subscriptions << subscription

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

    attr_accessor :subscription, :timestamp

    delegate :plan, :customer, to: :subscription

    def from_date
      return @from_date if @from_date.present?

      @from_date = case subscription.plan.interval.to_sym
                   when :weekly
                     (Time.zone.at(timestamp) - 1.week).to_date
                   when :monthly
                     (Time.zone.at(timestamp) - 1.month).to_date
                   when :yearly
                     (Time.zone.at(timestamp) - 1.year).to_date
                   else
                     raise NotImplementedError
                   end

      # NOTE: In case of termination or upgrade when we are terminating old plan(paying in arrear),
      # we should move to the beginning of the billing period
      if subscription.terminated? && subscription.plan.pay_in_arrear? && !subscription.downgraded?
        @from_date = compute_termination_from_date
      end

      # NOTE: On first billing period, subscription might start after the computed start of period
      #       ei: if we bill on beginning of period, and user registered on the 15th, the invoice should
      #       start on the 15th (subscription date) and not on the 1st
      @from_date = subscription.started_at.to_date if @from_date < subscription.started_at

      @from_date
    end

    def charges_from_date
      return @charges_from_date if @charges_from_date.present?

      @charges_from_date = if subscription.plan.yearly? && subscription.plan.bill_charges_monthly
        (Time.zone.at(timestamp) - 1.month).to_date
      else
        from_date
      end

      @charges_from_date = subscription.started_at.to_date if @charges_from_date < subscription.started_at

      @charges_from_date
    end

    def to_date
      return @to_date if @to_date.present?

      @to_date = (Time.zone.at(timestamp) - 1.day).to_date

      if subscription.terminated? && @to_date > subscription.terminated_at
        # NOTE: When subscription is terminated, we cannot generate an invoice for a period after the termination
        # TODO: from_date / to_date of invoices should be timestamps so that to_date = subscription.terminated_at
        @to_date = subscription.terminated_at.to_date - 1.day
      end

      # NOTE: When price plan is configured as `pay_in_advance`, subscription creation will be
      #       billed immediatly. An invoice must be generated for it with only the subscription fee.
      #       The invoicing period will be only one day: the subscription day
      @to_date = subscription.started_at.to_date if @to_date < subscription.started_at

      @to_date
    end

    def issuing_date
      return @issuing_date if @issuing_date.present?

      # NOTE: When price plan is configured as `pay_in_advance`, we issue the invoice for the first day of
      #       the period, it's on the last day otherwise
      @issuing_date = to_date

      @issuing_date = Time.zone.at(timestamp).to_date if subscription.plan.pay_in_advance?

      @issuing_date
    end

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = plan.amount_currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = plan.amount_currency
    end

    def create_subscription_fee(invoice)
      fee_result = Fees::SubscriptionService.new(invoice, subscription).create
      fee_result.throw_error unless fee_result.success?
    end

    def create_charges_fees(invoice)
      subscription.plan.charges.each do |charge|
        fee_result = Fees::ChargeService.new(invoice: invoice, charge: charge, subscription: subscription).create
        fee_result.throw_error unless fee_result.success?
      end
    end

    def should_create_subscription_fee?
      return false unless should_create_yearly_subscription_fee?

      # NOTE: When a subscription is terminated we still need to charge the subscription
      #       fee if the plan is in pay in arrear, otherwise this fee will never
      #       be created.
      subscription.active? || (subscription.terminated? && subscription.plan.pay_in_arrear?)
    end

    def should_create_yearly_subscription_fee?
      return true unless subscription.plan.yearly?

      # NOTE: we do not want to create a subscription fee for plans with bill_charges_monthly activated
      # But we want to keep the subscription charge when it has to proceed
      # Cases when we want to charge a subscription:
      #   - Plan is pay in advance, we're at the beginning of the period (month 1) or subscription has never been billed
      #   - Plan is pay in arrear and we're at the beginning of the period (month 1)
      Time.zone.at(timestamp).to_date.month == 1 || (subscription.plan.pay_in_advance && !subscription.already_billed?)
    end

    def should_create_charge_fees?(invoice)
      # NOTE: When a subscription is upgraded, the charges will be billed at the end of the period
      #       using the new subscription
      return false if subscription.terminated? && subscription.upgraded?

      # NOTE: Charges should not be billed in advance when we are just upgrading to a new
      #       pay_in_advance subscription
      return false if plan.pay_in_advance? && subscription.invoices.where.not(id: invoice.id).count.zero?

      true
    end

    def should_deliver_webhook?
      subscription.organization.webhook_url?
    end

    def applied_coupon
      return @applied_coupon if @applied_coupon

      @applied_coupon = customer.applied_coupons.active.first
    end

    def should_create_credit?
      return false if applied_coupon.nil?

      applied_coupon.amount_currency == plan.amount_currency
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

    def compute_termination_from_date
      case subscription.plan.interval.to_sym
      when :weekly
        Time.zone.at(timestamp).to_date.beginning_of_week
      when :monthly
        Time.zone.at(timestamp).to_date.beginning_of_month
      when :yearly
        Time.zone.at(timestamp).to_date.beginning_of_year
      else
        raise NotImplementedError
      end
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
          invoice_type: invoice.invoice_type
        }
      )
    end
  end
end
