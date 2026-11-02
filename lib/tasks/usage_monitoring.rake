# frozen_string_literal: true

namespace :usage_monitoring do
  desc "Announce the thresholds that subscription usage alerts passed before their creation baseline. " \
    "Usage: rake usage_monitoring:announce_missed_thresholds[from,to,organization_id] " \
    "(from and to filter on the alert created_at; omit organization_id to run for every organization). " \
    "Dry run unless DRY_RUN=false."
  task :announce_missed_thresholds, [:from, :to, :organization_id] => :environment do |_task, args|
    usage = "Usage: rake usage_monitoring:announce_missed_thresholds[from,to,organization_id]"
    abort usage if args[:from].blank? || args[:to].blank?

    from, to = [args[:from], args[:to]].map do |value|
      Time.zone.parse(value) || abort("Invalid from or to: #{value}. #{usage}")
    rescue ArgumentError
      abort "Invalid from or to: #{value}. #{usage}"
    end
    abort "from must be before to. #{usage}" if from > to

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    organization_id = args[:organization_id].presence

    puts "Announcing missed alert thresholds [#{mode}] for alerts created from #{from.iso8601} to #{to.iso8601} " \
      "(organization: #{organization_id || "all"})..."

    report = UsageMonitoring::AnnounceMissedThresholdsService.call!(from:, to:, organization_id:, dry_run:).report

    report.each do |entry|
      line = "  alert=#{entry[:alert_id]} organization=#{entry[:organization_id]} type=#{entry[:alert_type]} " \
        "code=#{entry[:alert_code]} status=#{entry[:status]} previous_value=#{entry[:previous_value].to_s("F")} " \
        "thresholds=#{entry[:thresholds].map { it.to_s("F") }.join(",")}"
      reason = entry[:reason] ? " reason=#{entry[:reason]}" : ""
      puts "#{line}#{reason}"
    end

    format_totals = ->(values) { values.tally.map { |key, count| "#{key}=#{count}" }.join(" ") }

    puts "Done [#{mode}]. Alerts considered: #{report.size}."
    puts "  Totals by status: #{format_totals.call(report.map { it[:status] })}"
    puts "  Totals by skip reason: #{format_totals.call(report.filter_map { it[:reason] })}"
  end
end
