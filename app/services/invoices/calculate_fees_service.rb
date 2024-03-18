# frozen_string_literal: true

module Invoices
  class CalculateFeesService < BaseService
    def initialize(invoice:, recurring: false, context: nil)
      @invoice = invoice
      @timestamp = invoice.invoice_subscriptions.first&.timestamp

      # NOTE: Billed automatically by the recurring billing process
      #       It is used to prevent double billing on billing day
      @recurring = recurring

      @context = context

      super
    end

    def call
      ActiveRecord::Base.transaction do
        invoice.invoice_subscriptions.each do |invoice_subscription|
          subscription = invoice_subscription.subscription
          date_service = Subscriptions::TerminatedDatesService.new(
            subscription:,
            invoice:,
            date_service: date_service(subscription),
          ).call

          boundaries = {
            from_datetime: invoice_subscription.from_datetime,
            to_datetime: invoice_subscription.to_datetime,
            charges_from_datetime: invoice_subscription.charges_from_datetime,
            charges_to_datetime: invoice_subscription.charges_to_datetime,
            timestamp: invoice_subscription.timestamp,
            charges_duration: date_service.charges_duration_in_days,
          }

          create_subscription_fee(subscription, boundaries) if should_create_subscription_fee?(subscription)
          create_charges_fees(subscription, boundaries) if should_create_charge_fees?(subscription)
          if should_create_minimum_commitment_true_up_fee?(invoice_subscription)
            create_minimum_commitment_true_up_fee(invoice_subscription)
          end
        end

        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees.sum(:amount_cents) -
                                                         invoice.coupons_amount_cents

        Credits::AppliedCouponsService.call(invoice:) if should_create_coupon_credit?
        Invoices::ComputeAmountsFromFees.call(invoice:)

        create_credit_note_credit if should_create_credit_note_credit?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.save!

        result.invoice = invoice.reload
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :subscriptions, :timestamp, :recurring, :context

    delegate :customer, :currency, to: :invoice

    def issuing_date
      timestamp.in_time_zone(customer.applicable_timezone).to_date
    end

    def date_service(subscription)
      Subscriptions::DatesService.new_instance(
        subscription,
        timestamp,
        current_usage: subscription.terminated? && subscription.upgraded?,
      )
    end

    def create_minimum_commitment_true_up_fee(invoice_subscription)
      minimum_commitment_result = Fees::Commitments::Minimum::CreateService.call(invoice_subscription:)
      minimum_commitment_result.raise_if_error!
    end

    def create_subscription_fee(subscription, boundaries)
      fee_result = Fees::SubscriptionService.new(invoice:, subscription:, boundaries:).create
      fee_result.raise_if_error!
    end

    def create_charges_fees(subscription, boundaries)
      subscription
        .plan
        .charges
        .includes(:billable_metric)
        .joins(:billable_metric)
        .where(invoiceable: true)
        .where
        .not(pay_in_advance: true, billable_metric: { recurring: false })
        .each do |charge|
          next if should_not_create_charge_fee?(charge, subscription)

          fee_result = Fees::ChargeService.new(invoice:, charge:, subscription:, boundaries:).create
          fee_result.raise_if_error!
        end
    end

    def should_not_create_charge_fee?(charge, subscription)
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
        charge_included_in_next_subscription?(charge, subscription)
    end

    # NOTE: If same charge is NOT included in upgraded plan we still want to bill it. However if new plan is using
    # the same charge it should not be billed since it is recurring and will be billed at the end of period
    def charge_included_in_next_subscription?(charge, subscription)
      return false if subscription.next_subscription.nil?

      next_subscription_charges = subscription.next_subscription.plan.charges

      return false if next_subscription_charges.blank?

      next_subscription_charges.pluck(:billable_metric_id).include?(charge.billable_metric_id)
    end

    def should_create_minimum_commitment_true_up_fee?(invoice_subscription)
      subscription = invoice_subscription.subscription

      return false if subscription.plan.pay_in_advance? && !invoice_subscription.previous_invoice_subscription
      return false unless should_create_yearly_subscription_fee?(subscription)

      calculate_true_up_fee_result = Commitments::Minimum::CalculateTrueUpFeeService
        .new_instance(invoice_subscription:).call

      return false if calculate_true_up_fee_result.amount_cents.zero?

      subscription.active? ||
        (
          subscription.terminated? &&
          (
            subscription.plan.pay_in_arrear? ||
            subscription.terminated_at >= invoice.created_at ||
            calculate_true_up_fee_result.amount_cents.positive?
          )
        )
    end

    def should_create_subscription_fee?(subscription)
      # NOTE: When plan is pay in advance we generate an invoice upon subscription creation
      # We want to prevent creating subscription fee if subscription creation already happened on billing day
      fee_exists = subscription.fees
        .subscription_kind
        .where(created_at: issuing_date.beginning_of_day..issuing_date.end_of_day)
        .where.not(invoice_id: invoice.id)
        .any?

      return false if subscription.plan.pay_in_advance? && fee_exists
      return false unless should_create_yearly_subscription_fee?(subscription)

      # NOTE: When a subscription is terminated we still need to charge the subscription
      #       fee if the plan is in pay in arrear, otherwise this fee will never
      #       be created.
      subscription.active? ||
        (subscription.terminated? && subscription.plan.pay_in_arrear?) ||
        (subscription.terminated? && subscription.terminated_at > invoice.created_at)
    end

    def should_create_yearly_subscription_fee?(subscription)
      return true unless subscription.plan.yearly?

      # NOTE: we do not want to create a subscription fee for plans with bill_charges_monthly activated
      # But we want to keep the subscription charge when it has to proceed
      # Cases when we want to charge a subscription:
      # - Plan is pay in advance, we're at the beginning of the period or subscription has never been billed
      # - Plan is pay in arrear and we're at the beginning of the period
      date_service(subscription).first_month_in_yearly_period? ||
        (subscription.plan.pay_in_advance && !subscription.already_billed?) ||
        (subscription.plan.pay_in_arrear? && subscription.terminated?)
    end

    def should_create_charge_fees?(subscription)
      # We should take a look at charges if subscription is created in the past and if it is not upgrade
      if subscription.plan.pay_in_advance? && subscription.started_in_past? && subscription.previous_subscription.nil?
        return true
      end

      # NOTE: Charges should not be billed in advance when we are just upgrading to a new
      #       pay_in_advance subscription
      return false if subscription.plan.pay_in_advance? && subscription.invoices.created_before(invoice).count.zero?

      true
    end

    def credit_notes
      @credit_notes ||= customer.credit_notes
        .finalized
        .available
        .where.not(invoice_id: invoice.id)
        .order(created_at: :asc)
    end

    def wallet
      return @wallet if @wallet

      @wallet = customer.wallets.active.first
    end

    def should_create_credit_note_credit?
      return false if not_in_finalizing_process?

      credit_notes.any?
    end

    def should_create_coupon_credit?
      return false if not_in_finalizing_process?
      return false unless invoice.fees_amount_cents&.positive?

      true
    end

    def should_create_applied_prepaid_credit?
      return false if not_in_finalizing_process?
      return false unless wallet&.active?
      return false unless invoice.total_amount_cents&.positive?

      wallet.balance.positive?
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.new(invoice:, credit_notes:).call
      credit_result.raise_if_error!

      refresh_amounts(credit_amount_cents: credit_result.credits.sum(&:amount_cents)) if credit_result.credits
    end

    def create_applied_prepaid_credit
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice:, wallet:)
      prepaid_credit_result.raise_if_error!

      refresh_amounts(credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
    end

    # NOTE: Since credit impact the invoice amount, we need to recompute the amount and the VAT amount
    def refresh_amounts(credit_amount_cents:)
      invoice.total_amount_cents -= credit_amount_cents
    end

    def not_in_finalizing_process?
      (invoice.draft? || invoice.voided?) && context != :finalize
    end
  end
end
