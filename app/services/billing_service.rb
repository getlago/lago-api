# frozen_string_literal: true

class BillingService
  def call
    subscriptions.find_each do |subscription|
      BillSubscriptionJob.perform_later(subscription)
    end
  end

  def subscriptions
    sql = []

    # =================================
    # Billed on the beginning of period
    # =================================
    if Time.zone.day == 1
      # Billed monthly
      sql << Subscription.joins(:plan)
        .merge(Plan.monthly.beginning_of_period)
        .select(:id).to_sql.to_sql

      # Billed yearly
      if Time.zone.month == 1
        sql << Subscription.joins(:plan)
          .merge(Plan.yearly.beginning_of_period)
          .select(:id).to_sql.to_sql
      end
    end

    # =================================
    # Billed on the subscription anniversary
    # =================================
    # Billed monthly
    days = [Time.zone.day]
    # If today is the last day of the month
    ((Time.zone.day + 1)..31).each { |day| days << day } if Time.zone.day == Time.zone.end_of_month.day

    sql << Subscription.joins(:plan)
      .merge(Plan.monthly.subscription_date)
      .where('DATE_PART(\'day\', subscriptions.started_at) IN (?)', days)
      .select(:id).to_sql

    # Billed yearly
    days = [Time.zone.day]

    # If we are not in leap year and we are on 28/02 take 29/02 into account
    days << 29 if !Date.leap?(Time.zone.year) && Time.zone.day == 28 && Time.zone.month == 2

    sql << Subscription.joins(:plan)
      .merge(Plan.yearly.subscription_date)
      .where('DATE_PART(\'month\', subscriptions.started_at) = ?', Time.zone.month)
      .where('DATE_PART(\'day\', subscriptions.started_at) IN (?)', days)
      .select(:id).to_sql

    Subscription.where("id in (#{sql.join(' UNION ')})")
  end
end
