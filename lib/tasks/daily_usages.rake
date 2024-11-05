# frozen_string_literal: true

require 'timecop'

namespace :daily_usages do
  desc "Fill past daily usage"
  task :fill_history, [:organization_id, :days_ago] => :environment do |_task, args|
    abort "Missing organization_id\n\n" unless args[:organization_id]

    Rails.logger.level = Logger::INFO

    days_ago = (args[:days_ago] || 120).to_i.days.ago
    organization = Organization.find(args[:organization_id])

    subscriptions = organization.subscriptions
      .where(status: [:active, :terminated])
      .where.not(started_at: nil)
      .where('terminated_at IS NULL OR terminated_at >= ?', days_ago)
      .includes(customer: :organization)

    subscriptions.find_each do |subscription|
      from = subscription.started_at.to_date
      if from < days_ago
        from = days_ago.to_date
      end

      to = (subscription.terminated_at || Time.current).to_date

      (from..to).each do |date|
        datetime = date.in_time_zone(subscription.customer.applicable_timezone).beginning_of_day.utc

        next if date == Date.today &&
          DailyUsage.refreshed_at_in_timezone(datetime).where(subscription_id: subscription.id).exists?

        Timecop.freeze(datetime + 5.minutes) do
          usage = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            apply_taxes: false,
            with_cache: false,
            max_to_datetime: datetime
          ).raise_if_error!.usage

          DailyUsage.create!(
            organization:,
            customer: subscription.customer,
            subscription:,
            external_subscription_id: subscription.external_id,
            usage: ::V1::Customers::UsageSerializer.new(usage, includes: %i[charges_usage]).serialize,
            from_datetime: usage.from_datetime,
            to_datetime: usage.to_datetime,
            refreshed_at: datetime
          )
        end
      end
    end
  end
end
