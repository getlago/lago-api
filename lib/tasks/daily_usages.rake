# frozen_string_literal: true

namespace :daily_usages do
  desc "Fill past daily usage"
  task :fill_history, [:organization_id, :days_ago] => :environment do |_task, args|
    abort "Missing organization_id\n\n" unless args[:organization_id]

    Rails.logger.level = Logger::INFO

    from_date = (args[:days_ago] || DailyUsage::DEFAULT_HISTORY_DAYS).days.ago.to_date
    organization = Organization.find(args[:organization_id])

    subscriptions = organization.subscriptions
      .where(status: [:active, :terminated])
      .where.not(started_at: nil)
      .where("terminated_at IS NULL OR terminated_at >= ?", from_date)
      .includes(customer: :organization)

    subscriptions.find_each do |subscription|
      DailyUsages::FillHistoryJob.perform_later(subscription:, from_date:)
    end
  end
end
