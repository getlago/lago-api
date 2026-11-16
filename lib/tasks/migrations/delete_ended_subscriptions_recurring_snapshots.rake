# frozen_string_literal: true

# Deletes the recurring aggregation snapshots of subscriptions terminated without a next subscription.
#
# Only a subscription and the one following it (an upgrade or a downgrade) read its snapshots, and the
# pruning of older periods runs on the next write of the same subscription, which never comes after a
# termination. Fees::ChargeService deletes them on the termination invoice from now on: this task removes
# the rows written before. A terminated subscription never gets a next one later, so the task is idempotent.
#
# Usage:
#   # 1. Preview for a single organization (no writes):
#   lago exec api bundle exec rails migrations:delete_ended_subscriptions_recurring_snapshots ORGANIZATION_ID=<uuid>
#
#   # 2. Apply for that organization:
#   lago exec api bundle exec rails migrations:delete_ended_subscriptions_recurring_snapshots \
#     DRY_RUN=false ORGANIZATION_ID=<uuid>
#
#   # 3. Apply for every organization (drop ORGANIZATION_ID):
#   lago exec api bundle exec rails migrations:delete_ended_subscriptions_recurring_snapshots DRY_RUN=false
class DeleteEndedSubscriptionsRecurringSnapshots
  def self.call(...) = new(...).call

  def initialize(organization_id: nil, dry_run: true)
    @organization_id = organization_id
    @dry_run = dry_run
  end

  # One entry per subscription, with the number of snapshots deleted, or that would be
  def call
    subscriptions.find_each.map do |subscription|
      snapshots = RecurringAggregationSnapshot.where(organization_id: subscription.organization_id, subscription_id: subscription.id)

      {
        subscription_id: subscription.id,
        organization_id: subscription.organization_id,
        snapshots_count: dry_run ? snapshots.count : snapshots.delete_all
      }
    end
  end

  private

  attr_reader :organization_id, :dry_run

  def subscriptions
    snapshots = RecurringAggregationSnapshot.all
    snapshots = snapshots.where(organization_id:) if organization_id

    scope = Subscription.terminated
      .where(id: snapshots.select(:subscription_id))
      .where.not(id: Subscription.where.not(status: :canceled).where.not(previous_subscription_id: nil).select(:previous_subscription_id))

    if organization_id
      scope.where(organization_id:)
    else
      scope
    end
  end
end

namespace :migrations do
  desc "Delete the recurring aggregation snapshots of subscriptions terminated without a next subscription. " \
    "Set ORGANIZATION_ID to run for one organization. Dry run unless DRY_RUN=false."
  task delete_ended_subscriptions_recurring_snapshots: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    organization_id = ENV["ORGANIZATION_ID"].presence

    puts "Deleting the recurring snapshots of subscriptions terminated without a next subscription [#{mode}] " \
      "(organization: #{organization_id || "all"})..."

    report = DeleteEndedSubscriptionsRecurringSnapshots.call(organization_id:, dry_run:)

    report.each do |entry|
      puts "  subscription=#{entry[:subscription_id]} organization=#{entry[:organization_id]} snapshots=#{entry[:snapshots_count]}"
    end

    puts "Done [#{mode}]. Subscriptions: #{report.size}, snapshots #{dry_run ? "to delete" : "deleted"}: " \
      "#{report.sum { it[:snapshots_count] }}."
  end
end
