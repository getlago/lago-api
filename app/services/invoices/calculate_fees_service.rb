# frozen_string_literal: true

module Invoices
  class CalculateFeesService < BaseService
    def initialize(invoice:, subscriptions:, timestamp:, recurring: false, context: nil)
      @invoice = invoice
      @subscriptions = subscriptions.uniq(&:id)
      @timestamp = timestamp

      # NOTE: Billed automatically by the recurring billing process
      #       It is used to prevent double billing on billing day
      @recurring = recurring

      @context = context

      super
    end

    def call
      if duplicated_invoices?
        return result.service_failure!(
          code: 'duplicated_invoices',
          message: 'Invoice subscription already exists with the boundaries',
        )
      end

      ActiveRecord::Base.transaction do
        subscriptions.each do |subscription|
          subscription_boundaries = subscriptions_boundaries[subscription.id]
          boundaries = termination_boundaries(subscription, subscription_boundaries)

          InvoiceSubscription.create!(
            invoice:,
            subscription:,
            timestamp: boundaries[:timestamp],
            from_datetime: boundaries[:from_datetime],
            to_datetime: boundaries[:to_datetime],
            charges_from_datetime: boundaries[:charges_from_datetime],
            charges_to_datetime: boundaries[:charges_to_datetime],
            recurring:,
          )

          create_subscription_fee(subscription, boundaries) if should_create_subscription_fee?(subscription)
          create_charges_fees(subscription, boundaries) if should_create_charge_fees?(subscription)
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
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
    end

    def date_service(subscription)
      Subscriptions::DatesService.new_instance(
        subscription,
        Time.zone.at(timestamp),
        current_usage: subscription.terminated? && subscription.upgraded?,
      )
    end

    def subscriptions_boundaries
      @subscriptions_boundaries ||= subscriptions.each_with_object({}) do |subscription, boundaries|
        boundaries[subscription.id] = calculate_boundaries(subscription)
      end
    end

    def duplicated_invoices?
      return false unless recurring

      subscriptions_boundaries.any? do |subscription_id, boundaries|
        subscription = Subscription.includes(:plan).find(subscription_id)

        matching_invoice_subscription?(subscription, boundaries)
      end
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
        subscription.plan.pay_in_advance && !subscription.already_billed?
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

    def calculate_boundaries(subscription)
      date_service = date_service(subscription)

      {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        timestamp: Time.zone.at(timestamp),
        charges_duration: date_service.charges_duration_in_days,
      }
    end

    def not_in_finalizing_process?
      (invoice.draft? || invoice.voided?) && context != :finalize
    end

    def matching_invoice_subscription?(subscription, boundaries)
      base_query = InvoiceSubscription
        .where(subscription_id: subscription.id)
        .recurring
        .where(from_datetime: boundaries[:from_datetime])
        .where(to_datetime: boundaries[:to_datetime])

      if subscription.plan.yearly? && subscription.plan.bill_charges_monthly?
        base_query = base_query
          .where(charges_from_datetime: boundaries[:charges_from_datetime])
          .where(charges_to_datetime: boundaries[:charges_to_datetime])
      end

      base_query.exists?
    end

    # This method calculates boundaries for terminated subscription. If termination is happening on billing date
    # new boundaries will be calculated only if there is no invoice subscription object for previous period.
    # Basically, we will bill regular subscription amount for previous period.
    # If subscription is happening on any other day, method is returning boundaries only for the used dates in
    # current period
    def termination_boundaries(subscription, boundaries)
      return boundaries unless subscription.terminated? && subscription.next_subscription.nil?

      # Date service has various checks for terminated subscriptions. We want to avoid it and fetch boundaries
      # for current usage (current period) but when subscription was active (one day ago)
      duplicate = subscription.dup.tap { |s| s.status = :active }

      current_time = Time.zone.at(timestamp)
      current_time_in_timezone = Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone)

      # First we need to ensure that termination date is not started_at date. In that case boundaries are correct
      # and we should bill only one day. If this is not the case we should proceed.
      return boundaries if (current_time_in_timezone - 1.day) < subscription.started_at

      dates_service = Subscriptions::DatesService.new_instance(duplicate, current_time - 1.day, current_usage: true)

      return boundaries if current_time_in_timezone < dates_service.charges_to_datetime
      return boundaries unless (current_time_in_timezone - dates_service.charges_to_datetime) < 1.day

      # We should calculate boundaries as if subscription was not terminated
      dates_service = Subscriptions::DatesService.new_instance(duplicate, current_time, current_usage: false)

      previous_period_boundaries = {
        from_datetime: dates_service.from_datetime,
        to_datetime: dates_service.to_datetime,
        charges_from_datetime: dates_service.charges_from_datetime,
        charges_to_datetime: dates_service.charges_to_datetime,
        timestamp: current_time,
        charges_duration: dates_service.charges_duration_in_days,
      }

      matching_invoice_subscription?(subscription, previous_period_boundaries) ? boundaries : previous_period_boundaries
    end
  end
end
