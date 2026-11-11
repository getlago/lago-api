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
        SELECT
          subscriptions.*,
          #{billed_since_trial_end} AS was_billed_since_trial_end
        FROM (#{subscriptions_in_trial}) AS subscriptions
          INNER JOIN customers ON customers.id = subscriptions.customer_id
          INNER JOIN billing_entities ON billing_entities.id = customers.billing_entity_id
        WHERE subscriptions.trial_end_utc_date_from_query#{at_time_zone} <= '#{timestamp}'#{at_time_zone}
      SQL

      Subscription.find_by_sql([sql, {timestamp:}])
    end

    # NOTE: Active subscriptions without trial_ended_at on a plan with a trial, with the end of their trial.
    #       The trial starts with the first subscription of the customer with the same external_id, terminated
    #       ones included, as in Subscription#initial_started_at, so an upgrade keeps it.
    #       ANY(ARRAY(...)) makes PostgreSQL find them through the index on (plan_id, status) instead of
    #       scanning every subscription.
    def subscriptions_in_trial
      <<-SQL
        SELECT
          subscriptions.*,
          (
            SELECT MIN(same_subscriptions.started_at)
            FROM subscriptions AS same_subscriptions
            WHERE same_subscriptions.customer_id = subscriptions.customer_id
              AND same_subscriptions.external_id = subscriptions.external_id
          ) + plans.trial_period * INTERVAL '1 day' AS trial_end_utc_date_from_query
        FROM subscriptions
          INNER JOIN plans ON plans.id = subscriptions.plan_id
        WHERE subscriptions.status = 1
          AND subscriptions.trial_ended_at IS NULL
          AND subscriptions.plan_id = ANY(ARRAY(SELECT plans.id FROM plans WHERE plans.trial_period > 0))
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
              BETWEEN DATE(subscriptions.trial_end_utc_date_from_query#{at_time_zone})
              AND DATE('#{timestamp}'#{at_time_zone})
        )
      SQL
    end
  end
end
