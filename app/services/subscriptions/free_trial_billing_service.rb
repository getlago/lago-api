# frozen_string_literal: true

module Subscriptions
  class FreeTrialBillingService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      ending_trial_subscriptions.each do |subscription|
        if subscription.plan_pay_in_advance && !already_billed?(subscription)
          BillSubscriptionJob.perform_later([subscription], timestamp)
        end

        subscription.update!(trial_ended_at: timestamp)

        SendWebhookJob.perform_later('subscription.trial_ended', subscription)
      end
    end

    private

    attr_reader :timestamp

    def already_billed?(subscription)
      # N+1
      # This is to avoid billing at the end of the trial if the customer was billed at the beginning
      # It's only for users who started billing customer AND upgraded their lago with this feature
      # during the customer trial period
      subscription.invoice_subscriptions.where(timestamp: subscription.started_at.all_day).exists?
    end

    def ending_trial_subscriptions
      sql = <<-SQL
        WITH
          initial_started_at AS (#{initial_started_at})
        SELECT DISTINCT
          plans.pay_in_advance AS plan_pay_in_advance,
          subscriptions.*
        FROM
          subscriptions
          INNER JOIN plans ON subscriptions.plan_id = plans.id
          INNER JOIN initial_started_at ON initial_started_at.external_id = subscriptions.external_id
          INNER JOIN customers ON subscriptions.customer_id = customers.id
          INNER JOIN organizations ON customers.organization_id = organizations.id
        WHERE
          subscriptions.status = 1
          AND subscriptions.trial_ended_at IS NULL
          AND DATE(initial_started_at#{at_time_zone} + plans.trial_period * INTERVAL '1 day') = DATE('#{timestamp}'#{at_time_zone})
      SQL

      Subscription.find_by_sql([sql, { timestamp: }])
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
  end
end
