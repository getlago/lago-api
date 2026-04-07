# frozen_string_literal: true

require "benchmark"
require "json"

namespace :enriched_events do
  desc "Compare ClickhouseStore vs ClickhouseEnrichedStore usage for given subscription IDs"
  task :compare, [:subscription_id] => :environment do |_task, args|
    Rails.logger.level = Logger::Severity::ERROR

    abort "Usage: [QUIET=true] [DEDUPLICATE=true] [FORMAT=json] rake enriched_events:compare[sub_id_1,sub_id_2,...]\n\n" unless args[:subscription_id]
    abort "[SKIP] Clickhouse is not enabled on this system" if ENV["LAGO_CLICKHOUSE_ENABLED"].blank?

    quiet = ENV.fetch("QUIET", "false") == "true"
    deduplicate = ENV.fetch("DEDUPLICATE", "false") == "true"
    format_json = ENV.fetch("FORMAT", "").downcase == "json"

    log = format_json ? ->(_msg) {} : ->(msg) { puts msg }
    json_results = [] if format_json

    subscription_ids = [args[:subscription_id]] + args.extras
    total_diffs = 0
    total_legacy_elapsed = 0.0
    total_enriched_elapsed = 0.0

    subscription_ids.each do |sub_id|
      log.call("\n#{"=" * 80}")
      log.call("Subscription: #{sub_id}")
      log.call("=" * 80)

      subscription = Subscription.includes(:customer, plan: :organization).find_by(id: sub_id)

      if subscription.nil?
        log.call("[SKIP] Subscription not found")
        json_results&.push({subscription_id: sub_id, status: "skipped", reason: "Subscription not found"})
        next
      end

      organization = subscription.plan.organization

      unless organization.clickhouse_events_store?
        log.call("[SKIP] Organization #{organization.id} does not use ClickHouse")
        json_results&.push({subscription_id: sub_id, status: "skipped", reason: "Organization does not use ClickHouse"})
        next
      end

      flag_was_enabled = organization.feature_flag_enabled?(:enriched_events_aggregation)
      legacy_fees = nil
      enriched_fees = nil
      legacy_elapsed = nil
      enriched_elapsed = nil

      begin
        ActiveRecord::Base.transaction do
          # Run with existing store (feature flag OFF)
          organization.disable_feature_flag!(:enriched_events_aggregation) if flag_was_enabled
          organization.update!(clickhouse_deduplication_enabled: deduplicate)
          organization.reload

          log.call("\nRunning legacy ClickhouseStore...")
          legacy_elapsed = Benchmark.realtime do
            legacy_result = Invoices::CustomerUsageService.call(
              customer: subscription.customer,
              subscription: subscription,
              with_cache: false,
              apply_taxes: false
            )

            if legacy_result.success?
              legacy_fees = legacy_result.usage.fees
            else
              log.call("[ERROR] Legacy usage computation failed: #{legacy_result.error&.message}")
            end
          end

          raise ActiveRecord::Rollback
        end

        ActiveRecord::Base.transaction do
          # Run with enriched store (feature flag ON)
          organization.enable_feature_flag!(:enriched_events_aggregation)
          organization.update!(clickhouse_deduplication_enabled: deduplicate, pre_filter_events: true)
          organization.reload

          log.call("Running enriched ClickhouseEnrichedStore...")
          enriched_elapsed = Benchmark.realtime do
            enriched_result = Invoices::CustomerUsageService.call(
              customer: subscription.customer,
              subscription: subscription,
              with_cache: false,
              apply_taxes: false
            )

            if enriched_result.success?
              enriched_fees = enriched_result.usage.fees
            else
              log.call("[ERROR] Enriched usage computation failed: #{enriched_result.error&.message}")
            end
          end

          raise ActiveRecord::Rollback
        end
      rescue => e
        log.call("[ERROR] Unexpected error: #{e.message}")
        log.call(e.backtrace.first(5).join("\n"))
        json_results&.push({subscription_id: sub_id, status: "error", reason: e.message})
        next
      end

      if legacy_fees.nil? || enriched_fees.nil?
        json_results&.push({subscription_id: sub_id, status: "error", reason: "One or both computations failed"})
        next
      end

      total_legacy_elapsed += legacy_elapsed
      total_enriched_elapsed += enriched_elapsed

      # Build lookup by composite key
      fee_key = ->(fee) {
        grouped = fee.grouped_by.presence || {}
        [fee.charge_id, fee.charge_filter_id, grouped]
      }

      legacy_by_key = legacy_fees.index_by { |f| fee_key.call(f) }
      enriched_by_key = enriched_fees.index_by { |f| fee_key.call(f) }

      all_keys = (legacy_by_key.keys + enriched_by_key.keys).uniq
      sub_diffs = 0
      fee_details = [] if format_json

      all_keys.each do |key|
        legacy_fee = legacy_by_key[key]
        enriched_fee = enriched_by_key[key]

        label = fee_label(legacy_fee || enriched_fee)

        if legacy_fee && !enriched_fee
          sub_diffs += 1
          log.call("  [ONLY IN LEGACY]  #{label}")
          if format_json
            fee_details << {
              charge_id: key[0], charge_filter_id: key[1], grouped_by: key[2], label: label,
              status: "only_in_legacy", legacy: fee_values(legacy_fee), enriched: nil, diffs: {}
            }
          end
        elsif enriched_fee && !legacy_fee
          sub_diffs += 1
          log.call("  [ONLY IN ENRICHED] #{label}")
          if format_json
            fee_details << {
              charge_id: key[0], charge_filter_id: key[1], grouped_by: key[2], label: label,
              status: "only_in_enriched", legacy: nil, enriched: fee_values(enriched_fee), diffs: {}
            }
          end
        else
          compared_fields = {
            units: [legacy_fee.units, enriched_fee.units],
            amount_cents: [legacy_fee.amount_cents, enriched_fee.amount_cents],
            events_count: [legacy_fee.events_count, enriched_fee.events_count],
            total_aggregated_units: [legacy_fee.total_aggregated_units, enriched_fee.total_aggregated_units]
          }

          diffs = compared_fields.select { |_, (l, e)| l != e }

          if diffs.empty?
            log.call("  [MATCH] #{label}") unless quiet
            if format_json && !quiet
              fee_details << {
                charge_id: key[0], charge_filter_id: key[1], grouped_by: key[2], label: label,
                status: "match", legacy: fee_values(legacy_fee), enriched: fee_values(enriched_fee), diffs: {}
              }
            end
          else
            sub_diffs += 1
            log.call("  [DIFF]  #{label}")
            if format_json
              diff_details = {}
              diffs.each do |field, (legacy_val, enriched_val)|
                delta = compute_delta(legacy_val, enriched_val)
                diff_details[field] = {legacy: legacy_val.to_s, enriched: enriched_val.to_s, delta: delta}
              end
              fee_details << {
                charge_id: key[0], charge_filter_id: key[1], grouped_by: key[2], label: label,
                status: "diff", legacy: fee_values(legacy_fee), enriched: fee_values(enriched_fee), diffs: diff_details
              }
            else
              diffs.each do |field, (legacy_val, enriched_val)|
                delta = compute_delta(legacy_val, enriched_val)
                log.call("          #{field}: legacy=#{legacy_val.inspect} enriched=#{enriched_val.inspect} (delta: #{delta})")
              end
            end
          end
        end
      end

      total_diffs += sub_diffs

      timing_info = build_timing(legacy_elapsed, enriched_elapsed)
      log.call("\n  Summary: #{all_keys.size} fee(s), #{sub_diffs} difference(s)")
      log.call("  Timing: legacy=#{legacy_elapsed.round(3)}s enriched=#{enriched_elapsed.round(3)}s #{timing_info[:comparison]}")

      if format_json
        json_results << {
          subscription_id: sub_id,
          status: "compared",
          timing: {legacy_seconds: legacy_elapsed.round(3), enriched_seconds: enriched_elapsed.round(3), speedup: timing_info[:speedup]},
          fee_count: all_keys.size,
          diff_count: sub_diffs,
          fees: fee_details
        }
      end
    end

    total_timing = build_timing(total_legacy_elapsed, total_enriched_elapsed)
    log.call("\n#{"=" * 80}")
    log.call("Total differences across all subscriptions: #{total_diffs}")
    log.call("Total timing: legacy=#{total_legacy_elapsed.round(3)}s enriched=#{total_enriched_elapsed.round(3)}s #{total_timing[:comparison]}")
    log.call("=" * 80)

    if format_json
      output = {
        generated_at: Time.current.iso8601,
        options: {quiet: quiet, deduplicate: deduplicate},
        total_diffs: total_diffs,
        total_subscriptions: subscription_ids.size,
        total_timing: {legacy_seconds: total_legacy_elapsed.round(3), enriched_seconds: total_enriched_elapsed.round(3), speedup: total_timing[:speedup]},
        subscriptions: json_results
      }
      puts JSON.pretty_generate(output)
    end
  end

  private

  def fee_values(fee)
    {
      units: fee.units.to_s,
      amount_cents: fee.amount_cents,
      events_count: fee.events_count,
      total_aggregated_units: fee.total_aggregated_units.to_s
    }
  end

  def build_timing(legacy_elapsed, enriched_elapsed)
    if enriched_elapsed.zero?
      {speedup: nil, comparison: "enriched=0s"}
    elsif legacy_elapsed.zero?
      {speedup: nil, comparison: "legacy=0s"}
    else
      speedup = (legacy_elapsed / enriched_elapsed).round(2)
      comparison = if speedup >= 1.0
        "speedup=#{speedup}x (enriched is faster)"
      else
        "slowdown=#{(1.0 / speedup).round(2)}x (enriched is slower)"
      end
      {speedup: speedup, comparison: comparison}
    end
  end

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
    parts << "from=#{fee.properties["charges_from_datetime"]}" if fee.properties["charges_from_datetime"]
    parts << "to=#{fee.properties["charges_to_datetime"]}" if fee.properties["charges_to_datetime"]
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
