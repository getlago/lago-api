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

    return Subscription.none unless today.day == 1

    # Billed monthly
    sql << Subscription.active.joins(:plan)
      .merge(Plan.monthly)
      .select(:id).to_sql

    # We are on the first day of the year
    if today.month == 1
      # Billed yearly
      sql << Subscription.active.joins(:plan)
        .merge(Plan.yearly)
        .select(:id).to_sql
    end

    Subscription.where("id in (#{sql.join(' UNION ')})")
  end
end
