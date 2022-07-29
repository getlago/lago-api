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

  # Retrieve list of subscription that should be billed today
  def billable_subscriptions
    sql = []
    today = Time.zone.now

    return Subscription.none unless (today.day == 1 || today.monday?)

    # For weekly interval we send invoices on Monday
    if today.monday?
      sql << Subscription.active.joins(:plan)
        .merge(Plan.weekly)
        .select(:id).to_sql
    end

    if today.day == 1
      # Billed monthly
      sql << Subscription.active.joins(:plan)
        .merge(Plan.monthly)
        .select(:id).to_sql

      # Bill charges monthly for yearly plans
      sql << Subscription.active.joins(:plan)
        .merge(Plan.yearly)
        .merge(Plan.where(bill_charges_monthly: true))
        .select(:id).to_sql

      # We are on the first day of the year
      if today.month == 1
        # Billed yearly
        sql << Subscription.active.joins(:plan)
          .merge(Plan.yearly)
          .select(:id).to_sql
      end
    end

    Subscription.where("id in (#{sql.join(' UNION ')})")
  end
end
