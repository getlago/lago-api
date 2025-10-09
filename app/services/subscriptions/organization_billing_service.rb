# frozen_string_literal: true

module Subscriptions
  class OrganizationBillingService < BaseService
    def initialize(organization:, billing_at: Time.current)
      @organization = organization
      @today = billing_at

      super
    end

    def call
      billable_subscriptions.group_by(&:customer_id).each do |_customer_id, customer_subscriptions|
        billing_subscriptions = []
        customer_subscriptions.each do |subscription|
          if subscription.next_subscription&.pending?
            # NOTE: In case of downgrade, subscription remain active until the end of the period,
            #       a next subscription is pending, the current one must be terminated
            Subscriptions::TerminateJob.perform_later(subscription, today.to_i)
          else
            billing_subscriptions << subscription
          end
        end

        BillSubscriptionJob.perform_later(
          billing_subscriptions,
          today.to_i,
          invoicing_reason: :subscription_periodic
        )

        BillNonInvoiceableFeesJob.perform_later(billing_subscriptions, today)
      end

      result
    end

    private

    attr_reader :today, :organization

    # NOTE: Retrieve list of subscriptions that should be billed today
    def billable_subscriptions
      sql = <<-SQL
        WITH
          billable_subscriptions AS (
            -- Calendar subscriptions
            (#{weekly_calendar})
            UNION
            (#{monthly_calendar})
            UNION
            (#{quarterly_calendar})
            UNION
            (#{semiannual_with_monthly_charges_calendar})
            UNION
            (#{semiannual_calendar})
            UNION
            (#{yearly_with_monthly_charges_calendar})
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
            (#{semiannual_with_monthly_charges_anniversary})
            UNION
            (#{semiannual_anniversary})
            UNION
            (#{yearly_with_monthly_charges_anniversary})
            UNION
            (#{yearly_anniversary})
          ),
          -- Filter subscriptions already billed today (in customer's applicable timezone)
          already_billed_today AS (#{already_billed_today})

        SELECT DISTINCT(subscriptions.*)
        FROM subscriptions
          INNER JOIN billable_subscriptions ON billable_subscriptions.subscription_id = subscriptions.id
          INNER JOIN customers ON customers.id = subscriptions.customer_id
          INNER JOIN organizations ON organizations.id = customers.organization_id
          INNER JOIN billing_entities ON billing_entities.id = customers.billing_entity_id
          LEFT JOIN already_billed_today ON already_billed_today.subscription_id = subscriptions.id
        WHERE
          organizations.id = '#{organization.id}'

          -- Exclude subscriptions already billed today
          AND already_billed_today.invoiced_count IS NULL

          -- Do not bill subscriptions that have started _after_ :today (excludes subscriptions starting today! and also importantly invoices that might have started after this service is run)
          AND DATE(subscriptions.started_at#{at_time_zone}) < DATE(:today#{at_time_zone})
          -- Do not bill subscriptions that were not created yet
          and DATE(subscriptions.created_at) <= Date(:today)
          AND (
            subscriptions.ending_at IS NULL OR
            DATE(subscriptions.ending_at#{at_time_zone}) != DATE(:today#{at_time_zone})
          )
        GROUP BY subscriptions.id
      SQL

      Subscription.find_by_sql([sql, {today:}])
    end

    def base_subscription_scope(billing_time: nil, interval: nil, conditions: nil)
      <<-SQL
        SELECT subscriptions.id AS subscription_id
        FROM subscriptions
          INNER JOIN plans ON plans.id = subscriptions.plan_id
          INNER JOIN customers ON customers.id = subscriptions.customer_id
          INNER JOIN billing_entities ON billing_entities.id = customers.billing_entity_id
          INNER JOIN organizations ON organizations.id = customers.organization_id
        WHERE subscriptions.status = #{Subscription.statuses[:active]}
          AND organizations.id = '#{organization.id}'
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
        conditions: ["EXTRACT(ISODOW FROM (:today#{at_time_zone})) = 1"]
      )
    end

    # NOTE: Billed monthly on 1st day of the month
    def monthly_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :monthly,
        conditions: ["DATE_PART('day', (:today#{at_time_zone})) = 1"]
      )
    end

    # NOTE: Billed quarterly on 1st day of the January, April, July and October
    def quarterly_calendar
      billing_month = <<-SQL
        (DATE_PART('month', (:today#{at_time_zone})) IN (1, 4, 7, 10))
      SQL

      billing_day = <<-SQL
        (DATE_PART('day', (:today#{at_time_zone})) = 1)
      SQL

      base_subscription_scope(
        billing_time: :calendar,
        interval: :quarterly,
        conditions: [billing_month, billing_day]
      )
    end

    # NOTE: Bill charges monthly for yearly plans on 1st day of the month
    def yearly_with_monthly_charges_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :yearly,
        conditions: [
          "DATE_PART('day', (:today#{at_time_zone})) = 1",
          "plans.bill_charges_monthly = 't'"
        ]
      )
    end

    # NOTE: Billed yearly on first day of the year
    def yearly_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :yearly,
        conditions: [
          "DATE_PART('month', (:today#{at_time_zone})) = 1",
          "DATE_PART('day', (:today#{at_time_zone})) = 1"
        ]
      )
    end

    # NOTE: Billed twice a year on 1st day of the January and July
    def semiannual_calendar
      billing_month = <<-SQL
        (DATE_PART('month', (:today#{at_time_zone})) IN (1, 7))
      SQL

      billing_day = <<-SQL
        (DATE_PART('day', (:today#{at_time_zone})) = 1)
      SQL

      base_subscription_scope(
        billing_time: :calendar,
        interval: :semiannual,
        conditions: [billing_month, billing_day]
      )
    end

    # NOTE: Bill charges monthly for semiannual plans on 1st day of the month
    def semiannual_with_monthly_charges_calendar
      base_subscription_scope(
        billing_time: :calendar,
        interval: :semiannual,
        conditions: [
          "DATE_PART('day', (:today#{at_time_zone})) = 1",
          "plans.bill_charges_monthly = 't'"
        ]
      )
    end

    def weekly_anniversary
      base_subscription_scope(
        billing_time: :anniversary,
        interval: :weekly,
        conditions: [
          "EXTRACT(ISODOW FROM (subscriptions.subscription_at#{at_time_zone})) =
          EXTRACT(ISODOW FROM (:today#{at_time_zone}))"
        ]
      )
    end

    def monthly_anniversary
      base_subscription_scope(
        billing_time: :anniversary,
        interval: :monthly,
        conditions: [<<-SQL]
          DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
            -- Check if today is the last day of the month
            CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :today#{at_time_zone})
            THEN
              -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
              (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :today#{at_time_zone})::integer, 31)))
            ELSE
              -- Otherwise, we just need the current day
              (SELECT ARRAY[DATE_PART('day', :today#{at_time_zone})])
            END
          )
        SQL
      )
    end

    # NOTE: Billed quarterly on anniversary date
    def quarterly_anniversary
      billing_day = <<-SQL
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          -- Check if today is the last day of the month
          CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :today#{at_time_zone})
          THEN
            -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
            (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :today#{at_time_zone})::integer, 31)))
          ELSE
            -- Otherwise, we just need the current day
            (SELECT ARRAY[DATE_PART('day', :today#{at_time_zone})])
          END
        )
      SQL

      billing_month = <<-SQL
        (
          -- We need to avoid zero and instead of it use 12. E.g.: (3 + 9) % 12 = 0 -> 12
          CASE WHEN MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) AS INTEGER), 3) = 0
          THEN
            (DATE_PART('month', :today#{at_time_zone}) IN (3, 6, 9, 12))
          ELSE (
            DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) = DATE_PART('month', :today#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 3 AS INTEGER), 12) = DATE_PART('month', :today#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 6 AS INTEGER), 12) = DATE_PART('month', :today#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 9 AS INTEGER), 12) = DATE_PART('month', :today#{at_time_zone})
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
        DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) = DATE_PART('month', :today#{at_time_zone})
      SQL

      billing_day = <<-SQL
        -- Check if we are not in a leap year when today is february the 28th
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          CASE WHEN (
            DATE_PART('month', :today#{at_time_zone}) = 2
            AND DATE_PART('day', :today#{at_time_zone}) = 28
            AND DATE_PART('day', (#{end_of_month})) = 28
          )
          THEN
            -- If not a leap year, we have to tale february the 29th into account
            ARRAY[28, 29]
          ELSE
            -- Otherwise, we just need the current day
            ARRAY[DATE_PART('day', :today#{at_time_zone})]
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :yearly,
        conditions: [billing_month, billing_day]
      )
    end

    def yearly_with_monthly_charges_anniversary
      billing_day = <<-SQL
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          -- Check if today is the last day of the month
          CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :today#{at_time_zone})
          THEN
            -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
            (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :today#{at_time_zone})::integer, 31)))
          ELSE
            -- Otherwise, we just need the current day
            (SELECT ARRAY[DATE_PART('day', :today#{at_time_zone})])
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :yearly,
        conditions: [
          "plans.bill_charges_monthly = 't'",
          billing_day
        ]
      )
    end

    def semiannual_anniversary
      billing_day = <<-SQL
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          -- Check if today is the last day of the month
          CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :today#{at_time_zone})
          THEN
            -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
            (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :today#{at_time_zone})::integer, 31)))
          ELSE
            -- Otherwise, we just need the current day
            (SELECT ARRAY[DATE_PART('day', :today#{at_time_zone})])
          END
        )
      SQL

      billing_month = <<-SQL
        (
          -- We need to avoid zero and instead of it use 12. E.g.: (3 + 9) % 12 = 0 -> 12
          CASE WHEN MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) AS INTEGER), 6) = 0
          THEN
            (DATE_PART('month', :today#{at_time_zone}) IN (6, 12))
          ELSE (
            DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) = DATE_PART('month', :today#{at_time_zone})
              OR MOD(CAST(DATE_PART('month', (subscriptions.subscription_at#{at_time_zone})) + 6 AS INTEGER), 12) = DATE_PART('month', :today#{at_time_zone})
          )
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :semiannual,
        conditions: [billing_month, billing_day]
      )
    end

    def semiannual_with_monthly_charges_anniversary
      billing_day = <<-SQL
        DATE_PART('day', (subscriptions.subscription_at#{at_time_zone})) = ANY (
          -- Check if today is the last day of the month
          CASE WHEN DATE_PART('day', (#{end_of_month})) = DATE_PART('day', :today#{at_time_zone})
          THEN
            -- If so and if it counts less than 31 days, we need to take all days up to 31 into account
            (SELECT ARRAY(SELECT generate_series(DATE_PART('day', :today#{at_time_zone})::integer, 31)))
          ELSE
            -- Otherwise, we just need the current day
            (SELECT ARRAY[DATE_PART('day', :today#{at_time_zone})])
          END
        )
      SQL

      base_subscription_scope(
        billing_time: :anniversary,
        interval: :semiannual,
        conditions: [
          "plans.bill_charges_monthly = 't'",
          billing_day
        ]
      )
    end

    def end_of_month
      <<-SQL
        (DATE_TRUNC('month', :today#{at_time_zone}) + INTERVAL '1 month - 1 day')::date
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
          INNER JOIN organizations AS org ON cus.organization_id = org.id
        WHERE invoice_subscriptions.recurring = 't'
          AND org.id = '#{organization.id}'
          AND invoice_subscriptions.timestamp IS NOT NULL
          AND DATE(
            (invoice_subscriptions.timestamp)#{at_time_zone(customer: "cus", billing_entity: "billing_entities")}
          ) = DATE(:today#{at_time_zone(customer: "cus", billing_entity: "billing_entities")})
        GROUP BY invoice_subscriptions.subscription_id
      SQL
    end
  end
end
