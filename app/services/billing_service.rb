# frozen_string_literal: true

class BillingService
  def call
    # Keep track of billing time for retry and tracking purpose
    billing_timestamp = Time.zone.now.to_i

    billable_subscriptions.group_by(&:customer_id).each do |_customer_id, customer_subscriptions|
      billing_subscriptions = []
      customer_subscriptions.each do |subscription|
        if subscription.next_subscription&.pending?
          # NOTE: In case of downgrade, subscription remain active until the end of the period,
          #       a next subscription is pending, the current one must be terminated
          Subscriptions::TerminateJob
            .set(wait: rand(240).minutes)
            .perform_later(subscription, billing_timestamp)
        else
          billing_subscriptions << subscription
        end
      end

      BillSubscriptionJob
        .set(wait: rand(240).minutes)
        .perform_later(billing_subscriptions, billing_timestamp)
    end
  end

  private

  def today
    @today ||= Time.current
  end

  # NOTE: Retrieve list of subscriptions that should be billed today
  def billable_subscriptions
    sql = []

    # NOTE: Calendar subscriptions

    # NOTE: For weekly interval we send invoices on Monday
    sql << weekly_calendar if today.monday?

    if today.day == 1
      # NOTE: Billed monthly
      sql << monthly_calendar

      # NOTE: Bill charges monthly for yearly plans
      sql << yearly_with_monthly_charges_calendar

      # NOTE: Billed yearly and we are on the first day of the year
      sql << yearly_calendar if today.month == 1
    end

    # NOTE: Anniversary subscriptions
    sql << weekly_anniversary
    sql << monthly_anniversary
    sql << yearly_with_monthly_charges_anniversary
    sql << yearly_anniversary

    Subscription.where("id in (#{sql.join(' UNION ')})")
  end

  def weekly_calendar
    Subscription.active.joins(:plan)
      .calendar
      .merge(Plan.weekly)
      .select(:id).to_sql
  end

  def monthly_calendar
    Subscription.active.joins(:plan)
      .calendar
      .merge(Plan.monthly)
      .select(:id).to_sql
  end

  def yearly_with_monthly_charges_calendar
    Subscription.active.joins(:plan)
      .calendar
      .merge(Plan.yearly.where(bill_charges_monthly: true))
      .select(:id).to_sql
  end

  def yearly_calendar
    Subscription.active.joins(:plan)
      .calendar
      .merge(Plan.yearly)
      .select(:id).to_sql
  end

  def weekly_anniversary
    Subscription.active.joins(:plan)
      .anniversary
      .merge(Plan.weekly)
      .where('EXTRACT(ISODOW FROM subscriptions.subscription_date) = ?', today.wday)
      .select(:id).to_sql
  end

  def monthly_anniversary
    days = [today.day]

    # If today is the last day of the month and month count less than 31 days,
    # we need to take all days up to 31 into account
    ((today.day + 1)..31).each { |day| days << day } if today.day == today.end_of_month.day

    Subscription.active.joins(:plan)
      .anniversary
      .merge(Plan.monthly)
      .where('DATE_PART(\'day\', subscriptions.subscription_date) IN (?)', days)
      .select(:id).to_sql
  end

  def yearly_anniversary
    # Billed yearly
    days = [today.day]

    # If we are not in leap year and we are on 28/02 take 29/02 into account
    days << 29 if !Date.leap?(today.year) && today.day == 28 && today.month == 2

    Subscription.active.joins(:plan)
      .anniversary
      .merge(Plan.yearly)
      .where('DATE_PART(\'month\', subscriptions.subscription_date) = ?', today.month)
      .where('DATE_PART(\'day\', subscriptions.subscription_date) IN (?)', days)
      .select(:id).to_sql
  end

  def yearly_with_monthly_charges_anniversary
    days = [today.day]

    # If today is the last day of the month and month count less than 31 days,
    # we need to take all days up to 31 into account
    ((today.day + 1)..31).each { |day| days << day } if today.day == today.end_of_month.day

    Subscription.active.joins(:plan)
      .anniversary
      .merge(Plan.yearly.where(bill_charges_monthly: true))
      .where('DATE_PART(\'day\', subscriptions.subscription_date) IN (?)', days)
      .select(:id).to_sql
  end
end
