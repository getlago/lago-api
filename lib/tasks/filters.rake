# frozen_string_literal: true

namespace :filters do
  desc "Clean duplicated filters"
  task deduplicate: :environment do
    charges = Charge.joins(:filters).includes(filters: {values: :billable_metric_filter}).distinct

    charges.find_each do |charge|
      next if charge.filters.count <= 1

      charge.filters.each do |filter|
        h = filter.to_h
        next if filter.reload.deleted_at.present?

        duplicates = charge.filters.select do |f|
          next false if f.id == filter.id
          next false if f.reload.deleted_at.present?

          h.keys.sort == f.to_h.keys.sort && h.keys.all? { |k| h[k].sort == f.to_h[k].sort }
        end

        duplicates.each { |f| f.discard! }
      end
    end
  end

  desc "Report, and with APPLY=true repair, charge filters that collapsed onto the same predicate"
  task discard_duplicates: :environment do
    organization = Organization.find(ENV.fetch("ORGANIZATION_ID"))
    plan = ENV["PLAN_ID"].present? ? organization.plans.find(ENV["PLAN_ID"]) : nil
    dry_run = ENV["APPLY"] != "true"
    keeper_strategy = ENV.fetch("KEEPER_STRATEGY", "intact_then_oldest")

    result = ChargeFilters::DiscardDuplicatesService.call(organization:, plan:, dry_run:, keeper_strategy:)

    if result.failure?
      abort "failed: #{result.error}"
    end

    price = ->(filter) { filter.properties.slice("amount", "rate", "pricing_group_keys", "grouped_by").compact }
    repairable, skipped = result.duplicate_groups.partition { !it.skipped? }

    scope = plan ? "organization #{organization.id} | plan #{plan.id}" : "organization #{organization.id}"

    puts "#{scope} | #{dry_run ? "DRY RUN" : "APPLY"} | keeper: #{keeper_strategy}"
    puts "duplicate groups #{result.duplicate_groups.size} | repairable #{repairable.size} | skipped #{skipped.size}"
    puts "filters discarded #{result.discarded_filter_ids.size}"

    # The same config mistake is copied into every override plan, so collapse the groups into the
    # distinct errors before printing them.
    puts "\nDISTINCT CONFIG ERRORS"
    repairable
      .group_by { [it.metric_code, it.predicate, price[it.keeper], it.filters_to_discard.map { |f| price[f] }.sort_by(&:to_s)] }
      .sort_by { |_key, groups| -groups.size }
      .each do |(code, predicate, keep_price, discard_prices), groups|
        puts "\n#{code} — #{groups.size} charges, #{groups.sum { it.filters_to_discard.size }} filters to discard"
        puts "  predicate #{predicate}"
        puts "  keep      #{keep_price}"
        puts "  discard   #{discard_prices.join(", ")}"
      end

    if skipped.any?
      puts "\nSKIPPED"
      skipped.group_by(&:skip_reason).each do |reason, groups|
        puts "  #{groups.size} groups: #{reason}"
        groups.first(10).each { puts "    charge #{it.charge_id} #{it.predicate}" }
      end
    end

    if dry_run
      puts "\nNothing changed. Re-run with APPLY=true to discard."
    else
      puts "\nDiscarded charge filter ids (keep these for rollback):"
      puts result.discarded_filter_ids.join(",")
    end
  end
end
