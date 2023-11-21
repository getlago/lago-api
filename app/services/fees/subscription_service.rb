# frozen_string_literal: true

module Fees
  class SubscriptionService < BaseService
    def initialize(invoice:, subscription:, boundaries:)
      @invoice = invoice
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)

      super(nil)
    end

    def create
      return result if already_billed?

      new_amount_cents = compute_amount.round

      new_fee = Fee.new(
        invoice:,
        subscription:,
        amount_cents: new_amount_cents,
        amount_currency: plan.amount_currency,
        fee_type: :subscription,
        invoiceable_type: 'Subscription',
        invoiceable: subscription,
        units: 1,
        properties: boundaries.to_h,
        payment_status: :pending,
        taxes_amount_cents: 0,
        unit_amount_cents: new_amount_cents,
      )
      new_fee.precise_unit_amount = new_fee.unit_amount.to_f
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :subscription, :boundaries

    delegate :customer, to: :invoice
    delegate :previous_subscription, :plan, to: :subscription

    def already_billed?
      existing_fee = invoice.fees.subscription_kind.find_by(subscription_id: subscription.id)
      return false unless existing_fee

      result.fee = existing_fee
      true
    end

    def compute_amount
      # NOTE: bill for the last time a subscription that was upgraded
      return terminated_amount if should_compute_terminated_amount?

      # NOTE: bill for the first time a subscription created after an upgrade
      return upgraded_amount if should_compute_upgraded_amount?

      # NOTE: bill a subscription on a full period
      return full_period_amount if should_use_full_amount?

      # NOTE: bill a subscription for the first time (or after downgrade)
      first_subscription_amount
    end

    def should_compute_terminated_amount?
      return false unless subscription.terminated?
      return false if subscription.plan.pay_in_advance?

      subscription.upgraded? || subscription.next_subscription.nil?
    end

    def should_compute_upgraded_amount?
      return false unless subscription.previous_subscription_id?
      return false if subscription.invoices.count > 1

      subscription.previous_subscription.upgraded?
    end

    # NOTE: Subscription has already been billed once and is not terminated
    #        or when it is payed in advance on an anniversary base
    def should_use_full_amount?
      # First condition covers case when plan is pay in advance and on anniversary base.
      # This case is used for the first subscription invoice since following cases will cover recurring invoices.
      # However, we should not bill full amount if subscription is downgraded since in that case, first invoice
      # should be prorated (this part is covered with first_subscription_amount method).
      return true if plan.pay_in_advance? && subscription.anniversary? && !subscription.previous_subscription_id
      return true if subscription.fees.subscription_kind.where('created_at < ?', invoice.created_at).exists?
      return true if subscription.started_in_past? && plan.pay_in_advance?

      if subscription.started_in_past? &&
         subscription.started_at < date_service(subscription).previous_beginning_of_period
        return true
      end

      false
    end

    def first_subscription_amount
      from_datetime = boundaries.from_datetime
      to_datetime = boundaries.to_datetime

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_datetime

        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_date > from_datetime) && (subscription.trial_end_date < to_datetime)
          from_datetime = subscription.initial_started_at + plan.trial_period.days
        end
      end

      # NOTE: Number of days of the first period since subscription creation
      days_to_bill = Utils::DatetimeService.date_diff_with_timezone(
        from_datetime,
        to_datetime,
        customer.applicable_timezone,
      )
      days_to_bill * single_day_price(subscription)
    end

    # NOTE: When terminating a pay in arrerar subscription, we need to
    #       bill the number of used day of the terminated subscription.
    #
    #       The amount to bill is computed with:
    #       **nb_day** = number of days between beggining of the period and the termination date
    #       **day_cost** = (plan amount_cents / full period duration)
    #       amount_to_bill = (nb_day * day_cost)
    def terminated_amount
      from_datetime = boundaries.from_datetime
      to_datetime = boundaries.to_datetime

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_datetime >= to_datetime

        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_datetime > from_datetime) && (subscription.trial_end_datetime < to_datetime)
          from_datetime = subscription.trial_end_datetime
        end
      end

      # NOTE: number of days between beginning of the period and the termination date
      number_of_day_to_bill = Utils::DatetimeService.date_diff_with_timezone(
        from_datetime,
        to_datetime,
        customer.applicable_timezone,
      )

      # Remove later customer timezone fix while passing optional_from_date
      # single_day_price method should return correct amount even without the timezone fix since
      # date service should not calculate single_day_price based on difference between dates but more as a
      # difference between date-times
      number_of_day_to_bill *
        single_day_price(
          subscription,
          optional_from_date: from_datetime.in_time_zone(customer.applicable_timezone).to_date,
        )
    end

    def upgraded_amount
      from_datetime = boundaries.from_datetime
      to_datetime = boundaries.to_datetime

      if plan.has_trial?
        return 0 if subscription.trial_end_datetime >= to_datetime

        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_datetime > from_datetime) && (subscription.trial_end_datetime < to_datetime)
          from_datetime = subscription.trial_end_datetime
        end
      end

      # NOTE: number of days between the upgrade and the end of the period
      number_of_day_to_bill = Utils::DatetimeService.date_diff_with_timezone(
        from_datetime,
        to_datetime,
        customer.applicable_timezone,
      )

      # NOTE: Subscription is upgraded from another plan
      #       We only bill the days between the upgrade date and the end of the period
      #       A credit note will apply automatically the amount of days from previous plan that were not consumed
      #
      #       The amount to bill is computed with:
      #       **nb_day** = number of days between upgrade and the end of the period
      #       **day_cost** = (plan amount_cents / full period duration)
      #       amount_to_bill = (nb_day * day_cost)
      number_of_day_to_bill * single_day_price(subscription)
    end

    def full_period_amount
      from_date = boundaries.from_datetime.to_date
      to_date = boundaries.to_datetime.to_date

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_date

        # NOTE: from_date is the trial end date if it happens during the period
        #       for this case, we should not apply the full period amount
        #       but the prorata between the trial end date end the invoice to_date
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          number_of_day_to_bill = (to_date + 1.day - subscription.trial_end_date).to_i

          return number_of_day_to_bill * single_day_price(subscription, optional_from_date: from_date)
        end
      end

      plan.amount_cents
    end

    def date_service(subscription)
      Subscriptions::DatesService.new_instance(subscription, Time.zone.at(boundaries.timestamp))
    end

    # NOTE: cost of a single day in a period
    def single_day_price(target_subscription, optional_from_date: nil)
      date_service(target_subscription).single_day_price(
        optional_from_date:,
      )
    end
  end
end
