# frozen_string_literal: true

module Fees
  class SubscriptionService < BaseService
    def initialize(invoice)
      @invoice = invoice
      super(nil)
    end

    def create
      return result if already_billed?

      new_amount_cents = compute_amount

      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        amount_cents: new_amount_cents,
        amount_currency: plan.amount_currency,
        vat_rate: plan.vat_rate,
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_reader :invoice

    delegate :plan, :subscription, to: :invoice
    delegate :previous_subscription, to: :subscription

    def already_billed?
      existing_fee = invoice.fees.subscription_kind.first
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

      subscription.upgraded?
    end

    def should_compute_upgraded_amount?
      return false unless subscription.previous_subscription_id?
      return false if subscription.invoices.count > 1

      subscription.previous_subscription.upgraded?
    end

    def should_use_full_amount?
      invoice.subscription.fees.subscription_kind.exists?
    end

    def first_subscription_amount
      from_date = invoice.from_date
      to_date = invoice.to_date

      # NOTE: When pay in advance, first invoice has from_date = to_date
      #       To get the number of days to bill, we must
      #       jump to the end of the billing period
      if plan.pay_in_advance?
        case plan.interval.to_sym
        when :monthly
          to_date = invoice.to_date.end_of_month
        when :yearly
          to_date = invoice.to_date.end_of_year
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

      (days_to_bill * single_day_price).to_i
    end

    # NOTE: When terminating a pay in arrerar subscription, we need to
    #       bill the number of used day of the terminated subscription.
    #
    #       The amount to bill is computed with:
    #       **nb_day** = number of days between beggining of the period and the termination date
    #       **day_cost** = (plan amount_cents / full period duration)
    #       amount_to_bill = (nb_day * day_cost)
    def terminated_amount
      from_date = invoice.from_date
      to_date = invoice.to_date

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_date

        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
        end
      end

      # NOTE: number of days between beggining of the period and the termination date
      number_of_day_to_bill = (to_date + 1.day - from_date).to_i

      (number_of_day_to_bill * single_day_price).to_i
    end

    def upgraded_amount
      from_date = invoice.from_date
      to_date = invoice.to_date

      if plan.has_trial?
        from_date = to_date + 1.day if subscription.trial_end_date >= to_date
        # NOTE: from_date is the trial end date if it happens during the period
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
        end
      end

      # NOTE: number of days between the upgrade and the end of the period
      number_of_day_to_bill = (to_date + 1.day - from_date).to_i

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
        old_day_price = single_day_price(previous_subscription.plan.amount_cents)

        (number_of_day_to_bill * (single_day_price - old_day_price)).to_i
      else
        # NOTE: Previous subscription was payed in arrear
        #       We only bill the days between the upgrade date and the end of the period
        #
        #       The amount to bill is computed with:
        #       **nb_day** = number of days between upgrade and the end of the period
        #       **day_cost** = (plan amount_cents / full period duration)
        #       amount_to_bill = (nb_day * day_cost)
        (number_of_day_to_bill * single_day_price).to_i
      end
    end

    def full_period_amount
      from_date = invoice.from_date
      to_date = invoice.to_date

      if plan.has_trial?
        # NOTE: amount is 0 if trial cover the full period
        return 0 if subscription.trial_end_date >= to_date

        # NOTE: from_date is the trial end date if it happens during the period
        #       for this case, we should not apply the full period amount
        #       but the prorata between the trial end date end the invoice to_date
        if (subscription.trial_end_date > from_date) && (subscription.trial_end_date < to_date)
          from_date = subscription.trial_end_date
          number_of_day_to_bill = (to_date + 1.day - from_date).to_i

          return (number_of_day_to_bill * single_day_price).to_i
        end
      end

      plan.amount_cents
    end

    # NOTE: cost of a single day in a period
    def single_day_price(amount_cents = plan.amount_cents)
      from_date = invoice.from_date

      # NOTE: Duration in days of full billed period (without termination)
      #       WARNING: the method only handles beggining of period logic
      duration = case plan.interval.to_sym
                 when :monthly
                   (from_date.end_of_month + 1.day) - from_date.beginning_of_month
                 when :yearly
                   (from_date.end_of_year + 1.day) - from_date.beginning_of_year
                 else
                   raise NotImplementedError
      end

      amount_cents.to_f / duration.to_i
    end
  end
end
