# frozen_string_literal: true

module Subscriptions
  class OrganizationEmitFixedChargeEventsService < BaseService
    def initialize(organization:, timestamp: Time.current)
      @organization = organization
      @timestamp = timestamp
      super
    end

    def call
      eligible_subscriptions_by_customer.each do |_customer_id, customer_subscriptions|
        emitting_subscriptions = []
        customer_subscriptions.each do |subscription|
          next if subscription.next_subscription&.pending?

          emitting_subscriptions << subscription
        end

        next if emitting_subscriptions.empty?

        Subscriptions::EmitFixedChargeEventsJob.perform_later(
          subscriptions: emitting_subscriptions,
          timestamp: timestamp.to_i
        )
      end

      result
    end

    private

    attr_reader :organization, :timestamp

    def eligible_subscriptions_by_customer
      eligible_subscriptions.group_by(&:customer_id)
    end

    # NOTE: Retrieve list of subscriptions that should have fixed charges
    #       events emitted on timestamp.
    def eligible_subscriptions
      sql = <<-SQL
        WITH
          emittable_subscriptions AS (
            -- Calendar subscriptions
            (#{weekly_calendar})
            UNION
            (#{monthly_calendar})
            UNION
            (#{quarterly_calendar})
            UNION
            (#{yearly_with_monthly_fixed_charges_calendar})
            UNION
            (#{yearly_calendar})

            UNION
            -- Anniversary subscriptions
            (#{weekly_anniversary})
            UNION
            (#{monthly_anniversary})
            UNION
            (#{quarterly_anniversary})
            UNION
            (#{yearly_with_monthly_fixed_charges_anniversary})
            UNION
            (#{yearly_anniversary})
          ),
          -- Filter fixed charges that already have events emitted on timestamp
          already_emitted_fixed_charges AS (#{already_emitted_fixed_charges})

        SELECT DISTINCT(subscriptions.*)
        FROM subscriptions
          INNER JOIN emittable_subscriptions ON emittable_subscriptions.subscription_id = subscriptions.id
          INNER JOIN plans ON plans.id = subscriptions.plan_id
          INNER JOIN fixed_charges ON fixed_charges.plan_id = plans.id
          INNER JOIN customers ON customers.id = subscriptions.customer_id
          INNER JOIN billing_entities ON billing_entities.id = customers.billing_entity_id
          LEFT JOIN already_emitted_fixed_charges ON (
            already_emitted_fixed_charges.subscription_id = subscriptions.id
            AND already_emitted_fixed_charges.fixed_charge_id = fixed_charges.id
          )
        WHERE
          subscriptions.organization_id = '#{organization.id}'

          -- Plan has fixed charges
          AND (
            fixed_charges.id IS NOT NULL AND
            (fixed_charges.deleted_at IS NULL OR fixed_charges.deleted_at > :timestamp)
          )

          -- Exclude fixed charges already emitted on timestamp
          AND already_emitted_fixed_charges.fixed_charge_id IS NULL

          -- Do not emit events for subscriptions that have started _after_ :timestamp (excludes subscriptions starting on timestamp! and also importantly subscriptions that might have started after this service is run)
          AND DATE(subscriptions.started_at#{at_time_zone}) < DATE(:timestamp#{at_time_zone})

          -- Do not bill subscriptions that were not created on timestamp
          AND DATE(subscriptions.created_at) <= Date(:timestamp)

          -- Do not bill subscriptions that are ending on timestamp
          AND (
            subscriptions.ending_at IS NULL OR
            DATE(subscriptions.ending_at#{at_time_zone}) != DATE(:timestamp#{at_time_zone})
          )

        GROUP BY subscriptions.id
      SQL

      Subscription.find_by_sql([sql, {timestamp:}])
    end

    def at_time_zone(customer: "customers", billing_entity: "billing_entities")
      <<-SQL
        AT TIME ZONE COALESCE(#{customer}.timezone, #{billing_entity}.timezone, 'UTC')
      SQL
    end

    def base_subscription_scope(billing_time: nil, interval: nil, conditions: nil)
      <<-SQL
        SELECT subscriptions.id AS subscription_id
        FROM subscriptions
          INNER JOIN plans ON plans.id = subscriptions.plan_id
          INNER JOIN customers ON customers.id = subscriptions.customer_id
          INNER JOIN billing_entities ON billing_entities.id = customers.billing_entity_id
        WHERE subscriptions.organization_id = '#{organization.id}'
          AND subscriptions.status = #{Subscription.statuses[:active]}
          AND subscriptions.billing_time = #{Subscription.billing_times[billing_time]}
          AND plans.interval = #{Plan.intervals[interval]}
          AND #{conditions.join(" AND ")}
        GROUP BY subscriptions.id
      SQL
    end

    # NOTE: For weekly interval we send invoices on Monday (ISODOW = 1)
    def weekly_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :weekly,
        conditions: ["EXTRACT(ISODOW FROM (:timestamp#{at_time_zone})) = 1"]
      )
    end

    # NOTE: Billed monthly on 1st day of the month
    def monthly_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :monthly,
        conditions: ["DATE_PART('day', (:timestamp#{at_time_zone})) = 1"]
      )
    end

    # NOTE: Billed quarterly on 1st day of the January, April, July and October
    def quarterly_calendar
      billing_month = <<-SQL
        (DATE_PART('month', (:timestamp#{at_time_zone})) IN (1, 4, 7, 10))
      SQL

      billing_day = <<-SQL
        (DATE_PART('day', (:timestamp#{at_time_zone})) = 1)
      SQL

      base_subscription_scope(
        billing_time: :calendar,
        interval: :quarterly,
        conditions: [billing_month, billing_day]
      )
    end

    # NOTE: Bill fixed charges monthly for yearly plans on 1st day of the month
    def yearly_with_monthly_fixed_charges_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :yearly,
        conditions: [
          "DATE_PART('day', (:timestamp#{at_time_zone})) = 1",
          "plans.bill_fixed_charges_monthly = 't'"
        ]
      )
    end

    # NOTE: Billed yearly on first day of the year
    def yearly_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :yearly,
        conditions: [
          "DATE_PART('month', (:timestamp#{at_time_zone})) = 1",
          "DATE_PART('day', (:timestamp#{at_time_zone})) = 1"
        ]
      )
    end

    def weekly_anniversary
      base_subscription_scope(
        billing_time: :anniversary,
        interval: :weekly,
        conditions: [
          "EXTRACT(ISODOW FROM (subscriptions.subscription_at#{at_time_zone})) =
          EXTRACT(ISODOW FROM (:timestamp#{at_time_zone}))"
        ]
      )
    end

    def monthly_anniversary
      base_subscription_scope(
        billing_time: :anniversary,
        interval: :monthly,
        conditions: [<<-SQL]
          DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
            -- Check if timestamp is the last day of the month
            CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :timestamp#{at_time_zone})
            THEN
              -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
              (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :timestamp#{at_time_zone})::integer, 31)))
            ELSE
              -- Otherwise, we just need the current day
              (SELECT ARRAY[DATE_PART('day', :timestamp#{at_time_zone})])
            END
          )
        SQL
      )
    end

    # NOTE: Billed quarterly on anniversary date
    def quarterly_anniversary
      billing_day = <<-SQL
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          -- Check if timestamp is the last day of the month
          CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :timestamp#{at_time_zone})
          THEN
            -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
            (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :timestamp#{at_time_zone})::integer, 31)))
          ELSE
            -- Otherwise, we just need the current day
            (SELECT ARRAY[DATE_PART('day', :timestamp#{at_time_zone})])
          END
        )
      SQL

      billing_month = <<-SQL
        (
          -- We need to avoid zero and instead of it use 12. E.g.: (3 + 9) % 12 = 0 -> 12
          CASE WHEN MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) AS INTEGER), 3) = 0
          THEN
            (DATE_PART('month', :timestamp#{at_time_zone}) IN (3, 6, 9, 12))
          ELSE (
            DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) = DATE_PART('month', :timestamp#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 3 AS INTEGER), 12) = DATE_PART('month', :timestamp#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 6 AS INTEGER), 12) = DATE_PART('month', :timestamp#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 9 AS INTEGER), 12) = DATE_PART('month', :timestamp#{at_time_zone})
          )
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :quarterly,
        conditions: [billing_month, billing_day]
      )
    end

    def yearly_anniversary
      billing_month = <<-SQL
        -- Ensure we are on the billing month
        DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) = DATE_PART('month', :timestamp#{at_time_zone})
      SQL

      billing_day = <<-SQL
        -- Check if we are not in a leap year when timestamp is february the 28th
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          CASE WHEN (
            DATE_PART('month', :timestamp#{at_time_zone}) = 2
            AND DATE_PART('day', :timestamp#{at_time_zone}) = 28
            AND DATE_PART('day', (#{end_of_month})) = 28
          )
          THEN
            -- If not a leap year, we have to tale february the 29th into account
            ARRAY[28, 29]
          ELSE
            -- Otherwise, we just need the current day
            ARRAY[DATE_PART('day', :timestamp#{at_time_zone})]
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :yearly,
        conditions: [billing_month, billing_day]
      )
    end

    def yearly_with_monthly_fixed_charges_anniversary
      billing_day = <<-SQL
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          -- Check if timestamp is the last day of the month
          CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :timestamp#{at_time_zone})
          THEN
            -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
            (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :timestamp#{at_time_zone})::integer, 31)))
          ELSE
            -- Otherwise, we just need the current day
            (SELECT ARRAY[DATE_PART('day', :timestamp#{at_time_zone})])
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :yearly,
        conditions: [
          "plans.bill_fixed_charges_monthly = 't'",
          billing_day
        ]
      )
    end

    def end_of_month
      <<-SQL
        (DATE_TRUNC('month', :timestamp#{at_time_zone}) + INTERVAL '1 month - 1 day')::date
      SQL
    end

    def already_emitted_fixed_charges
      <<-SQL
        SELECT DISTINCT
          fixed_charge_events.subscription_id,
          fixed_charge_events.fixed_charge_id
        FROM fixed_charge_events
          INNER JOIN subscriptions ON fixed_charge_events.subscription_id = subscriptions.id
          INNER JOIN customers ON subscriptions.customer_id = customers.id
          INNER JOIN billing_entities ON customers.billing_entity_id = billing_entities.id
        WHERE fixed_charge_events.deleted_at IS NULL
          AND fixed_charge_events.organization_id = '#{organization.id}'
          AND fixed_charge_events.timestamp IS NOT NULL
          AND DATE(fixed_charge_events.timestamp#{at_time_zone}) = DATE(:timestamp#{at_time_zone})
      SQL
    end
  end
end
