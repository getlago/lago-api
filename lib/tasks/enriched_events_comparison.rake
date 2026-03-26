# frozen_string_literal: true

namespace :enriched_events do
  desc "Compare ClickhouseStore vs ClickhouseEnrichedStore usage for given subscription IDs"
  task :compare, [:subscription_id] => :environment do |_task, args|
    Rails.logger.level = Logger::Severity::ERROR

    abort "Usage: [QUIET=true] [DEDUPLICATE=true] rake enriched_events:compare[sub_id_1,sub_id_2,...]\n\n" unless args[:subscription_id]
    abort "[SKIP] Clickhouse is not enabled on this system" if ENV["LAGO_CLICKHOUSE_ENABLED"].blank?

    quiet = ENV.fetch("QUIET", "false") == "true"
    deduplicate = ENV.fetch("DEDUPLICATE", "false") == "true"

    subscription_ids = [args[:subscription_id]] + args.extras
    total_diffs = 0

    subscription_ids.each do |sub_id|
      puts "\n#{"=" * 80}"
      puts "Subscription: #{sub_id}"
      puts "=" * 80

      subscription = Subscription.includes(:customer, plan: :organization).find_by(id: sub_id)

      if subscription.nil?
        puts "[SKIP] Subscription not found"
        next
      end

      organization = subscription.plan.organization

      unless organization.clickhouse_events_store?
        puts "[SKIP] Organization #{organization.id} does not use ClickHouse"
        next
      end

      flag_was_enabled = organization.feature_flag_enabled?(:enriched_events_aggregation)
      legacy_fees = nil
      enriched_fees = nil

      begin
        ActiveRecord::Base.transaction do
          # Run with existing store (feature flag OFF)
          organization.disable_feature_flag!(:enriched_events_aggregation) if flag_was_enabled
          organization.update!(clickhouse_deduplication_enabled: deduplicate)
          organization.reload

          puts "\nRunning legacy ClickhouseStore..."
          legacy_result = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            with_cache: false,
            apply_taxes: false
          )

          if legacy_result.success?
            legacy_fees = legacy_result.usage.fees
          else
            puts "[ERROR] Legacy usage computation failed: #{legacy_result.error&.message}"
          end

          raise ActiveRecord::Rollback
        end

        ActiveRecord::Base.transaction do
          # Run with enriched store (feature flag ON)
          organization.enable_feature_flag!(:enriched_events_aggregation)
          organization.update!(clickhouse_deduplication_enabled: deduplicate)
          organization.reload

          puts "Running enriched ClickhouseEnrichedStore..."
          enriched_result = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            with_cache: false,
            apply_taxes: false
          )

          if enriched_result.success?
            enriched_fees = enriched_result.usage.fees
          else
            puts "[ERROR] Enriched usage computation failed: #{enriched_result.error&.message}"
          end

          raise ActiveRecord::Rollback
        end
      rescue => e
        puts "[ERROR] Unexpected error: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        next
      end

      next if legacy_fees.nil? || enriched_fees.nil?

      # Build lookup by composite key
      fee_key = ->(fee) {
        grouped = fee.grouped_by.presence || {}
        [fee.charge_id, fee.charge_filter_id, grouped]
      }

      legacy_by_key = legacy_fees.index_by { |f| fee_key.call(f) }
      enriched_by_key = enriched_fees.index_by { |f| fee_key.call(f) }

      all_keys = (legacy_by_key.keys + enriched_by_key.keys).uniq
      sub_diffs = 0

      all_keys.each do |key|
        legacy_fee = legacy_by_key[key]
        enriched_fee = enriched_by_key[key]

        label = fee_label(legacy_fee || enriched_fee)

        if legacy_fee && !enriched_fee
          sub_diffs += 1
          puts "  [ONLY IN LEGACY]  #{label}"
        elsif enriched_fee && !legacy_fee
          sub_diffs += 1
          puts "  [ONLY IN ENRICHED] #{label}"
        else
          compared_fields = {
            units: [legacy_fee.units, enriched_fee.units],
            amount_cents: [legacy_fee.amount_cents, enriched_fee.amount_cents],
            events_count: [legacy_fee.events_count, enriched_fee.events_count],
            total_aggregated_units: [legacy_fee.total_aggregated_units, enriched_fee.total_aggregated_units]
          }

          diffs = compared_fields.select { |_, (l, e)| l != e }

          if diffs.empty?
            puts "  [MATCH] #{label}" unless quiet
          else
            sub_diffs += 1
            puts "  [DIFF]  #{label}"
            diffs.each do |field, (legacy_val, enriched_val)|
              delta = compute_delta(legacy_val, enriched_val)
              puts "          #{field}: legacy=#{legacy_val.inspect} enriched=#{enriched_val.inspect} (delta: #{delta})"
            end
          end
        end
      end

      total_diffs += sub_diffs
      puts "\n  Summary: #{all_keys.size} fee(s), #{sub_diffs} difference(s)"
    end

    puts "\n#{"=" * 80}"
    puts "Total differences across all subscriptions: #{total_diffs}"
    puts "=" * 80
  end

  private

  def fee_label(fee)
    parts = ["charge=#{fee.charge_id}"]
    if fee.billable_metric
      parts << "metric=#{fee.billable_metric.code}"
      parts << "agg=#{fee.billable_metric.aggregation_type}"
    end
    parts << "model=#{fee.charge&.charge_model}" if fee.charge
    parts << "filter=#{fee.charge_filter.to_h} filter_id=#{fee.charge_filter_id}" if fee.charge_filter_id
    grouped = fee.grouped_by.presence
    parts << "grouped_by=#{grouped}" if grouped
    parts.join(" ")
  end

  def compute_delta(legacy_val, enriched_val)
    return "N/A" if legacy_val.nil? || enriched_val.nil?

    diff = enriched_val.to_d - legacy_val.to_d
    if legacy_val.to_d.zero?
      diff.zero? ? "0" : "#{diff} (from zero)"
    else
      pct = (diff / legacy_val.to_d * 100).round(4)
      "#{diff} (#{pct}%)"
    end
  rescue
    "N/A"
  end
end
