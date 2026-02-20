# frozen_string_literal: true

namespace :migrations do
  desc "Migrate usage thresholds from child plans to subscriptions or remove duplicates"
  task :migrate_usage_thresholds, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake migrations:migrate_usage_thresholds[organization_id]" unless organization_id

    organization = Organization.find(organization_id)

    threshold_signature = ->(thresholds) { thresholds.map { |t| [t.amount_cents, t.recurring] }.sort }

    parent_plans = organization.plans.parents
      .joins(:entitlements)
      .distinct

    total_deleted = 0
    total_moved = 0

    parent_plans.find_each do |parent_plan|
      parent_signature = threshold_signature.call(parent_plan.usage_thresholds)

      subscriptions = organization.subscriptions
        .joins(:plan)
        .where(plans: {parent_id: parent_plan.id})
        .includes(plan: :usage_thresholds)

      subscriptions.find_each do |subscription|
        child_plan = subscription.plan
        child_thresholds = child_plan.usage_thresholds.to_a
        next if child_thresholds.empty?

        child_signature = threshold_signature.call(child_thresholds)

        if child_signature == parent_signature
          deleted_count = child_plan.usage_thresholds.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          total_deleted += deleted_count
          puts "Deleted #{deleted_count} redundant thresholds from child plan #{child_plan.id}"
        else
          if subscription.usage_thresholds.none?
            child_thresholds.each do |threshold|
              UsageThreshold.create!(
                organization:,
                subscription:,
                amount_cents: threshold.amount_cents,
                recurring: threshold.recurring,
                threshold_display_name: threshold.threshold_display_name
              )
            end
            total_moved += child_thresholds.size
          end

          deleted_count = child_plan.usage_thresholds.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          total_deleted += deleted_count
          puts "Moved thresholds from child plan #{child_plan.id} to subscription #{subscription.id}"
        end
      end
    end

    puts "Done. Deleted #{total_deleted} child plan thresholds, created #{total_moved} subscription thresholds."
  end
end
