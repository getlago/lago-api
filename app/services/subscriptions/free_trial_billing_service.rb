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
        if subscription.plan.pay_in_advance? && !subscription_fee_billed_for_period?(subscription)
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

      result
    end

    private

    attr_reader :timestamp

    def subscription_fee_billed_for_period?(subscription)
      date_service = Subscriptions::DatesService.new_instance(subscription, Time.zone.at(timestamp))

      subscription
        .fees
        .subscription
        .joins(:invoice).where.not(invoices: {status: %i[voided deleted]})
        .where(
          "date_trunc('second', (properties->>'from_datetime')::timestamptz) = date_trunc('second', ?::timestamptz)",
          date_service.from_datetime&.iso8601(3)
        )
        .where(
          "date_trunc('second', (properties->>'to_datetime')::timestamptz) = date_trunc('second', ?::timestamptz)",
          date_service.to_datetime&.iso8601(3)
        )
        .exists?
    end

    def ending_trial_subscriptions
      sql = <<-SQL
        WITH
          initial_started_at AS (#{initial_started_at})
        SELECT DISTINCT
          plans.pay_in_advance AS plan_pay_in_advance,
          #{trial_end_date} as trial_end_utc_date_from_query,
          subscriptions.*
        FROM
          subscriptions
          INNER JOIN plans ON subscriptions.plan_id = plans.id
          INNER JOIN initial_started_at ON initial_started_at.external_id = subscriptions.external_id
          INNER JOIN customers ON subscriptions.customer_id = customers.id
          INNER JOIN billing_entities ON customers.billing_entity_id = billing_entities.id
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
  end
end
