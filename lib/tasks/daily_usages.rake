# frozen_string_literal: true

require 'timecop'

namespace :daily_usages do
  desc "Fill past daily usage"
  task :fill_history, [:organization_id] => :environment do |_task, args|
    abort "Missing organization_id\n\n" unless args[:organization_id]

    organization = Organization.find(args[:organization_id])

    subscriptions = organization.subscriptions
      .where(status: [:active, :terminated])
      .where.not(started_at: nil)
      .where('terminated_at IS NULL OR terminated_at >= ?', 4.months.ago)
      .includes(:customer)

    subscriptions.find_each do |subscription|
      from = subscription.started_at.to_date
      if from < 4.months.ago
        from = 4.months.ago.to_date
      end

      to = (subscription.terminated_at || Time.current).to_date

      (from..to).each do |date|
        datetime = date + 5.minutes

        Timecop.freeze(datetime) do
          usage = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            apply_taxes: false,
            with_cache: false,
            max_to_datetime: date.beginning_of_day
          ).raise_if_error!.usage

          DailyUsage.create!(
            organization:,
            customer: subscription.customer,
            subscription:,
            external_subscription_id: subscription.external_id,
            usage: ::V1::Customers::UsageSerializer.new(usage, includes: %i[charges_usage]).serialize,
            from_datetime: usage.from_datetime,
            to_datetime: usage.to_datetime,
            refreshed_at: date
          )
        end
      end
    end
  end
end
