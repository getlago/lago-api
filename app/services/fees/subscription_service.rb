# frozen_string_literal: true

module Fees
  class SubscriptionService < BaseService
    WEEK_DURATION = 7.freeze

    def initialize(invoice, subscription, boundaries)
      @invoice = invoice
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)

      super(nil)
    end

    def create
      return result if already_billed?

      new_amount_cents = compute_amount

      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        amount_cents: new_amount_cents.round,
        amount_currency: plan.amount_currency,
        vat_rate: customer.applicable_vat_rate,
        units: 1,
        properties: boundaries.to_h
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
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
    def should_use_full_amount?
      subscription.fees.subscription_kind.exists?
    end

    def first_subscription_amount
      from_date = boundaries.from_date
      to_date = boundaries.to_date

      # NOTE: When pay in advance, first invoice has from_date = to_date
      #       To get the number of days to bill, we must
      #       jump to the end of the billing period
      if plan.pay_in_advance?
        case plan.interval.to_sym
        when :weekly
          to_date = boundaries.to_date.end_of_week
        when :monthly
          to_date = boundaries.to_date.end_of_month
        when :yearly
          to_date = boundaries.to_date.end_of_year
        else
          raise NotImplementedError
        end
      end

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_date

        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
        end
      end

      # NOTE: Number of days of the first period since subscription creation
      days_to_bill = (to_date + 1.day - from_date).to_i

      days_to_bill * single_day_price(plan)
    end

    # NOTE: When terminating a pay in arrerar subscription, we need to
    #       bill the number of used day of the terminated subscription.
    #
    #       The amount to bill is computed with:
    #       **nb_day** = number of days between beggining of the period and the termination date
    #       **day_cost** = (plan amount_cents / full period duration)
    #       amount_to_bill = (nb_day * day_cost)
    def terminated_amount
      from_date = boundaries.from_date
      to_date = boundaries.to_date

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_date

        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
        end
      end

      # NOTE: number of days between beginning of the period and the termination date
      number_of_day_to_bill = (to_date + 1.day - from_date).to_i

      number_of_day_to_bill * single_day_price(plan)
    end

    def upgraded_amount
      from_date = boundaries.from_date
      to_date = compute_to_date(boundaries.to_date, plan)
      old_to_date = compute_to_date(boundaries.to_date, previous_subscription.plan)

      if plan.has_trial?
        from_date = to_date + 1.day if subscription.trial_end_date >= to_date
        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
        end
      end

      # NOTE: number of days between the upgrade and the end of the period
      new_number_of_day_to_bill = (to_date + 1.day - from_date).to_i
      old_number_of_day_to_bill = (old_to_date + 1.day - from_date).to_i

      if previous_subscription.plan.pay_in_advance?
        # NOTE: Previous subscription was payed in advance
        #       We have to bill the difference between old plan and new plan cost on the
        #       period between upgrade date and the end of the period
        #
        #       The amount to bill is computed with:
        #       **nb_day** = number of days between current date and end of period
        #       **old_day_price** = (old plan amount_cents / full period duration)
        #       **new_day_price** = (new plan amount_cents / full period duration)
        #       amount_to_bill = nb_day * (new_day_price - old_day_price)
        old_day_price = single_day_price(previous_subscription.plan)

        amount = new_number_of_day_to_bill * single_day_price(plan) - old_number_of_day_to_bill * old_day_price

        return 0 if amount.negative?

        amount
      else
        # NOTE: Previous subscription was payed in arrear
        #       We only bill the days between the upgrade date and the end of the period
        #
        #       The amount to bill is computed with:
        #       **nb_day** = number of days between upgrade and the end of the period
        #       **day_cost** = (plan amount_cents / full period duration)
        #       amount_to_bill = (nb_day * day_cost)
        new_number_of_day_to_bill * single_day_price(plan)
      end
    end

    def full_period_amount
      from_date = boundaries.from_date
      to_date = boundaries.to_date

      if plan.has_trial?
        if plan.pay_in_advance?
          from_date = invoice.issuing_date
          to_date = invoice.issuing_date.end_of_month
        end

        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_date

        # NOTE: from_date is the trial end date if it happens during the period
        #       for this case, we should not apply the full period amount
        #       but the prorata between the trial end date end the invoice to_date
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
          number_of_day_to_bill = (to_date + 1.day - from_date).to_i

          return number_of_day_to_bill * single_day_price(plan, from_date)
        end
      end

      plan.amount_cents
    end

    # NOTE: cost of a single day in a period
    def single_day_price(target_plan, optional_from_date = nil)
      from_date = optional_from_date || boundaries.from_date

      # NOTE: Duration in days of full billed period (without termination)
      #       WARNING: the method only handles beginning of period logic
      duration = case target_plan.interval.to_sym
                 when :weekly
                   WEEK_DURATION
                 when :monthly
                   (from_date.end_of_month + 1.day) - from_date.beginning_of_month
                 when :yearly
                   (from_date.end_of_year + 1.day) - from_date.beginning_of_year
                 else
                   raise NotImplementedError
      end

      target_plan.amount_cents.fdiv(duration.to_i)
    end

    def compute_to_date(base_date, plan)
      return base_date if plan.pay_in_arrear?

      # NOTE: when plan is pay in advance, the to date should be the
      # end of the actual period
      case plan.interval.to_sym
      when :weekly
        boundaries.to_date.end_of_week
      when :monthly
        boundaries.to_date.end_of_month
      when :yearly
        boundaries.to_date.end_of_year
      else
        raise NotImplementedError
      end
    end
  end
end
