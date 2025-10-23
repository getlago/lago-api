# frozen_string_literal: true

module Subscriptions
  class FreeTrialBillingService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      # we need more tests :see_no_evil
      ending_trial_subscriptions.each do |subscription|
        if subscription.should_be_billed_when_started? &&
            !subscription.was_already_billed_today &&
            !already_billed_on_day_one?(subscription)
          BillSubscriptionJob.perform_later(
            [subscription],
            timestamp,
            invoicing_reason: :subscription_starting,
            skip_charges: true
          )
        end

        subscription.update!(trial_ended_at: subscription.trial_end_utc_date_from_query)

        SendWebhookJob.perform_later("subscription.trial_ended", subscription)

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end
      end
    end

    private

    attr_reader :timestamp

    # This is to avoid billing at the end of the trial if the customer was billed at the beginning
    # It's only for users who started billing customer AND upgraded their lago with this feature
    # during the customer trial period
    # Unfortunately, this introduces an N+1 query
    def already_billed_on_day_one?(subscription)
      Fee.where(fee_type: [:subscription, :fixed_charge]).where(
        invoice_id: subscription.invoice_subscriptions.select("invoices.id").joins(:invoice).where(
          "invoices.invoice_type" => :subscription,
          "invoices.status" => %i[draft finalized],
          :timestamp => subscription.started_at.all_day
        )
      ).any?
    end

    def ending_trial_subscriptions
      sql = <<-SQL
        WITH
          initial_started_at AS (#{initial_started_at}),
          already_billed_today AS (#{already_billed_today})
        SELECT DISTINCT
          plans.pay_in_advance AS plan_pay_in_advance,
          already_billed_today.invoiced_count > 0 AS was_already_billed_today,
          #{trial_end_date} as trial_end_utc_date_from_query,
          CASE WHEN pay_in_advance_fixed_charges.fixed_charge_id IS NOT NULL THEN true ELSE false END AS has_pay_in_advance_fixed_charges,
          subscriptions.*
        FROM
          subscriptions
          INNER JOIN plans ON subscriptions.plan_id = plans.id
          INNER JOIN initial_started_at ON initial_started_at.external_id = subscriptions.external_id
          INNER JOIN customers ON subscriptions.customer_id = customers.id
          INNER JOIN billing_entities ON customers.billing_entity_id = billing_entities.id
          LEFT JOIN already_billed_today ON already_billed_today.subscription_id = subscriptions.id
          LEFT JOIN (
            SELECT DISTINCT plan_id, id as fixed_charge_id
            FROM fixed_charges
            WHERE pay_in_advance = true AND deleted_at IS NULL
          ) pay_in_advance_fixed_charges ON pay_in_advance_fixed_charges.plan_id = plans.id
        WHERE
          subscriptions.status = 1
          AND plans.trial_period > 0
          AND subscriptions.trial_ended_at IS NULL
          AND #{trial_end_date + at_time_zone} <= '#{timestamp}'#{at_time_zone}
      SQL

      Subscription.find_by_sql([sql, {timestamp:}])
    end

    def initial_started_at
      <<-SQL
        SELECT
          external_id,
          FIRST_VALUE(started_at) OVER (PARTITION BY external_id ORDER BY started_at) AS initial_started_at
        FROM
          subscriptions
      SQL
    end

    def trial_end_date
      <<-SQL
        (initial_started_at + plans.trial_period * INTERVAL '1 day')
      SQL
    end

    def already_billed_today
      <<-SQL
        SELECT
          invoice_subscriptions.subscription_id,
          COUNT(invoice_subscriptions.id) AS invoiced_count
        FROM invoice_subscriptions
          INNER JOIN subscriptions AS sub ON invoice_subscriptions.subscription_id = sub.id
          INNER JOIN customers AS cus ON sub.customer_id = cus.id
          INNER JOIN billing_entities ON cus.billing_entity_id = billing_entities.id
        WHERE invoice_subscriptions.recurring = 't'
          AND invoice_subscriptions.timestamp IS NOT NULL
          AND DATE(
            (invoice_subscriptions.timestamp)#{at_time_zone(customer: "cus", billing_entity: "billing_entities")}
          ) = DATE('#{timestamp}'#{at_time_zone(customer: "cus", billing_entity: "billing_entities")})
        GROUP BY invoice_subscriptions.subscription_id
      SQL
    end
  end
end
