# frozen_string_literal: true

class BillingService
  def call
    # Keep track of billing time for retry and tracking purpose
    billing_timestamp = Time.zone.now.to_i

    billable_subscriptions.find_each do |subscription|
      BillSubscriptionJob
        .set(wait: rand(240).minutes)
        .perform_later(subscription, billing_timestamp)
    end
  end

  private

  # Retrieve list of subscription that should be billed today
  def billable_subscriptions
    sql = []
    today = Time.zone.now

    # =================================
    # Billed on the beginning of period
    # =================================
    # We are on the first day of the month
    if today.day == 1
      # Billed monthly
      sql << Subscription.active.joins(:plan)
        .merge(Plan.monthly.beginning_of_period)
        .select(:id).to_sql

      # We are on the first day of the year
      if today.month == 1
        # Billed yearly
        sql << Subscription.active.joins(:plan)
          .merge(Plan.yearly.beginning_of_period)
          .select(:id).to_sql
      end
    end

    # =================================
    # Billed on the subscription anniversary
    # =================================

    # Billed monthly
    days = [today.day]

    # If today is the last day of the month and month count less than 31 days,
    # we need to take all days up to 31 into account
    ((today.day + 1)..31).each { |day| days << day } if today.day == today.end_of_month.day

    sql << Subscription.active.joins(:plan)
      .merge(Plan.monthly.subscription_date)
      .where('DATE_PART(\'day\', subscriptions.anniversary_date) IN (?)', days)
      .select(:id).to_sql

    # Billed yearly
    days = [today.day]

    # If we are not in leap year and we are on 28/02 take 29/02 into account
    days << 29 if !Date.leap?(today.year) && today.day == 28 && today.month == 2

    sql << Subscription.active.joins(:plan)
      .merge(Plan.yearly.subscription_date)
      .where('DATE_PART(\'month\', subscriptions.anniversary_date) = ?', today.month)
      .where('DATE_PART(\'day\', subscriptions.anniversary_date) IN (?)', days)
      .select(:id).to_sql

    # Query subscriptions by ids
    Subscription.where("id in (#{sql.join(' UNION ')})")
  end
end
