# frozen_string_literal: true

module Subscriptions
  class FreeTrialBillingService < BaseService
    Result = BaseResult

    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      ending_trial_subscriptions.each do |subscription|
        if !subscription.was_billed_since_trial_end &&
            !already_billed_on_day_one?(subscription)

          if subscription.plan.pay_in_advance?
            BillSubscriptionJob.perform_later(
              [subscription],
              timestamp,
              invoicing_reason: :subscription_starting,
              skip_charges: true
            )
          end
        end

        subscription.update!(trial_ended_at: subscription.trial_end_utc_date_from_query)

        SendWebhookJob.perform_later("subscription.trial_ended", subscription)

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end
      end

      result
    end

    private

    attr_reader :timestamp

    # This is to avoid billing at the end of the trial if the customer was billed at the beginning
    # It's only for users who started billing customer AND upgraded their lago with this feature
    # during the customer trial period
    # Unfortunately, this introduces an N+1 query
    def already_billed_on_day_one?(subscription)
      Fee.subscription.where(
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
          trial_plans AS (SELECT plans.id FROM plans WHERE plans.trial_period > 0),
          initial_started_at AS (#{initial_started_at})
        SELECT
          #{billed_since_trial_end} AS was_billed_since_trial_end,
          #{trial_end_date} as trial_end_utc_date_from_query,
          subscriptions.*
        FROM
          subscriptions
          INNER JOIN plans ON subscriptions.plan_id = plans.id
          INNER JOIN initial_started_at
            ON initial_started_at.customer_id = subscriptions.customer_id
            AND initial_started_at.external_id = subscriptions.external_id
          INNER JOIN customers ON subscriptions.customer_id = customers.id
          INNER JOIN billing_entities ON customers.billing_entity_id = billing_entities.id
        WHERE
          #{in_trial}
          AND #{trial_end_date + at_time_zone} <= '#{timestamp}'#{at_time_zone}
      SQL

      Subscription.find_by_sql([sql, {timestamp:}])
    end

    # NOTE: Same lookup as Subscription#initial_started_at, for the customer and external_id pairs that have a
    #       subscription in trial. It reads every subscription of those pairs, terminated ones included, so an
    #       upgrade keeps the start of the first subscription.
    def initial_started_at
      <<-SQL
        SELECT
          subscriptions.customer_id,
          subscriptions.external_id,
          MIN(subscriptions.started_at) AS initial_started_at
        FROM
          subscriptions
        WHERE (subscriptions.customer_id, subscriptions.external_id) IN (
          SELECT subscriptions.customer_id, subscriptions.external_id
          FROM subscriptions
          WHERE #{in_trial}
        )
        GROUP BY subscriptions.customer_id, subscriptions.external_id
      SQL
    end

    # NOTE: Shared by the outer query and the initial_started_at CTE, which must select the same subscriptions.
    #       Each use has its own FROM subscriptions, so the name always refers to the nearest one.
    #       ANY(ARRAY(...)) makes PostgreSQL find them through the index on (plan_id, status) instead of
    #       scanning every subscription.
    def in_trial
      <<-SQL
        subscriptions.status = 1
        AND subscriptions.trial_ended_at IS NULL
        AND subscriptions.plan_id = ANY(ARRAY(SELECT trial_plans.id FROM trial_plans))
      SQL
    end

    def trial_end_date
      <<-SQL
        (initial_started_at + plans.trial_period * INTERVAL '1 day')
      SQL
    end

    # NOTE: Matches a recurring invoice issued from the trial end day through the run day.
    #       - Run day: the renewal issued just before this run, after the trial ended.
    #       - Trial end day: the job runs hourly, so a trial ending late in the day is processed
    #         after midnight, when the renewal issued on the trial end day is no longer "today".
    #       Both renewals already include the in-advance subscription fee.
    def billed_since_trial_end
      <<-SQL
        EXISTS (
          SELECT 1
          FROM invoice_subscriptions
          WHERE invoice_subscriptions.subscription_id = subscriptions.id
            AND invoice_subscriptions.recurring = 't'
            AND invoice_subscriptions.timestamp IS NOT NULL
            AND DATE((invoice_subscriptions.timestamp)#{at_time_zone})
              BETWEEN DATE(#{trial_end_date + at_time_zone})
              AND DATE('#{timestamp}'#{at_time_zone})
        )
      SQL
    end
  end
end
