# frozen_string_literal: true

class BillingService
  def call
    # Keep track of billing time for retry and tracking purpose
    billing_timestamp = Time.current.to_i

    billable_subscriptions.group_by(&:customer_id).each do |_customer_id, customer_subscriptions|
      billing_subscriptions = []
      customer_subscriptions.each do |subscription|
        if subscription.next_subscription&.pending?
          # NOTE: In case of downgrade, subscription remain active until the end of the period,
          #       a next subscription is pending, the current one must be terminated
          Subscriptions::TerminateJob
            .set(wait: rand(50).minutes)
            .perform_later(subscription, billing_timestamp)
        else
          billing_subscriptions << subscription
        end
      end

      BillSubscriptionJob
        .set(wait: rand(50).minutes)
        .perform_later(billing_subscriptions, billing_timestamp, invoice_source: :recurring)
    end
  end

  private

  def today
    @today ||= Time.current
  end

  # NOTE: Retrieve list of subscriptions that should be billed today
  def billable_subscriptions
    sql = [
      # NOTE: Calendar subscriptions
      weekly_calendar,
      monthly_calendar,
      yearly_with_monthly_charges_calendar,
      yearly_calendar,

      # NOTE: Anniversary subscriptions
      weekly_anniversary,
      monthly_anniversary,
      yearly_with_monthly_charges_anniversary,
      yearly_anniversary,
    ]

    # NOTE: Prevent double billing by excluding subscription already billed
    #       or started today
    sql_ids = Subscription.where("subscriptions.id in (#{sql.join(' UNION ')})")
      .joins(customer: :organization)
      .joins("LEFT JOIN (#{already_billed_filter_sql}) insub ON insub.subscription_id = subscriptions.id")
      .where(insub: { invoiced_count: nil })
      .where.not("DATE(#{Subscription.started_at_in_timezone_sql}) = ?", today.to_date)
      .group(:id)
      .select(:id)
      .to_sql

    Subscription.where("id in (#{sql_ids})")
  end

  def base_subscription_scope
    Subscription
      .active
      .joins(:plan, customer: :organization)
      .group('subscriptions.id')
      .select(:id)
  end

  # NOTE: For weekly interval we send invoices on Monday (ISODOW = 1)
  def weekly_calendar
    base_subscription_scope
      .calendar
      .merge(Plan.weekly)
      .where("EXTRACT(ISODOW FROM (#{today_shift_sql})) = 1", today)
      .to_sql
  end

  # NOTE: Billed monthly on 1st day of the month
  def monthly_calendar
    base_subscription_scope
      .calendar
      .merge(Plan.monthly)
      .where("DATE_PART('day', (#{today_shift_sql})) = 1", today)
      .to_sql
  end

  # NOTE: Bill charges monthly for yearly plans on 1st day of the month
  def yearly_with_monthly_charges_calendar
    base_subscription_scope
      .calendar
      .merge(Plan.yearly.where(bill_charges_monthly: true))
      .where("DATE_PART('day', (#{today_shift_sql})) = 1", today)
      .to_sql
  end

  # NOTE: Billed yearly on first day of the year
  def yearly_calendar
    base_subscription_scope
      .calendar
      .merge(Plan.yearly)
      .where("DATE_PART('month', (#{today_shift_sql})) = 1", today)
      .where("DATE_PART('day', (#{today_shift_sql})) = 1", today)
      .to_sql
  end

  def weekly_anniversary
    base_subscription_scope
      .anniversary
      .merge(Plan.weekly)
      .where("EXTRACT(ISODOW FROM (#{Subscription.subscription_at_in_timezone_sql})) = ?", today.wday)
      .to_sql
  end

  def monthly_anniversary
    days = [today.day]

    # If today is the last day of the month and month count less than 31 days,
    # we need to take all days up to 31 into account
    ((today.day + 1)..31).each { |day| days << day } if today.day == today.end_of_month.day

    base_subscription_scope
      .anniversary
      .merge(Plan.monthly)
      .where("DATE_PART('day', (#{Subscription.subscription_at_in_timezone_sql})) IN (?)", days)
      .to_sql
  end

  def yearly_anniversary
    # Billed yearly
    days = [today.day]

    # If we are not in leap year and we are on 28/02 take 29/02 into account
    days << 29 if !Date.leap?(today.year) && today.day == 28 && today.month == 2

    base_subscription_scope
      .anniversary
      .merge(Plan.yearly)
      .where("DATE_PART('month', (#{Subscription.subscription_at_in_timezone_sql})) = ?", today.month)
      .where("DATE_PART('day', (#{Subscription.subscription_at_in_timezone_sql})) IN (?)", days)
      .to_sql
  end

  def yearly_with_monthly_charges_anniversary
    days = [today.day]

    # If today is the last day of the month and month count less than 31 days,
    # we need to take all days up to 31 into account
    ((today.day + 1)..31).each { |day| days << day } if today.day == today.end_of_month.day

    base_subscription_scope
      .anniversary
      .merge(Plan.yearly.where(bill_charges_monthly: true))
      .where("DATE_PART('day', (#{Subscription.subscription_at_in_timezone_sql})) IN (?)", days)
      .to_sql
  end

  def today_shift_sql
    <<-SQL
      ?::timestamptz AT TIME ZONE
      COALESCE(customers.timezone, organizations.timezone, 'UTC')
    SQL
  end

  def already_billed_filter_sql
    InvoiceSubscription
      .where("DATE(invoice_subscriptions.properties->>'timestamp') = DATE(?)", today.to_date)
      .recurring
      .group(:subscription_id)
      .select('invoice_subscriptions.subscription_id, COUNT(invoice_subscriptions.id) AS invoiced_count')
      .to_sql
  end
end
