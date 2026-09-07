# frozen_string_literal: true

namespace :events do
  # NOTE: related to https://github.com/getlago/lago-api/issues/317
  desc "Fill missing timestamps for events"
  task fill_timestamp: :environment do
    Event.unscoped.where(timestamp: nil).find_each do |event|
      event.update!(timestamp: event.created_at)
    end
  end

  desc "Fill missing subscription_id"
  task fill_subscription: :environment do
    Event.unscoped.where(subscription_id: nil).find_each do |event|
      subscription = event.customer.active_subscription || event.customer.subscriptions.order(:created_at).last

      unless subscription
        event.destroy
        next
      end

      event.update!(subscription_id: subscription.id)
    end
  end

  desc "Deduplicate events_enriched_expanded by removing older versions of duplicate rows"
  task deduplicate_enriched_expanded: :environment do
    Rails.logger.level = Logger::Severity::INFO

    organization_id = ENV.fetch("ORGANIZATION_ID")
    subscription_ids = ENV["SUBSCRIPTION_IDS"].to_s.split(",").map(&:strip).reject(&:blank?)
    codes = ENV["BM_CODES"].to_s.split(",").map(&:strip).reject(&:blank?)
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    quiet = ENV.fetch("QUIET", "false") == "true"
    timeout = ENV["TIMEOUT"].presence

    organization = Organization.find(organization_id)
    subscriptions = organization.subscriptions
    subscriptions = subscriptions.where(id: subscription_ids) if subscription_ids.present?

    total_duplicates = 0

    subscriptions.find_each do |subscription|
      service = Events::Stores::Clickhouse::CleanDuplicatedEnrichedExpandedService.new(subscription:, codes:, timeout: timeout.to_i.positive? ? timeout.to_i : nil)

      duplicate_count = service.count_duplicates

      if dry_run
        if duplicate_count > 0 || !quiet
          Rails.logger.info(
            "events:deduplicate_enriched_expanded [DRY RUN] - Subscription #{subscription.external_id}: #{duplicate_count} duplicate rows would be removed"
          )
        end
      else
        begin
          result = service.call
          duplicate_count = result.duplicated_count

          if duplicate_count > 0 || !quiet
            message = "duplicate rows will be removed"
            message = "#{duplicate_count} have to be removed" if result.queries.present?

            Rails.logger.info(
              "events:deduplicate_enriched_expanded - Subscription #{subscription.external_id}: #{duplicate_count} #{message}"
            )
          end

          if result.queries.present?
            Rails.logger.warn(
              "events:deduplicate_enriched_expanded - Subscription #{subscription.external_id}: " \
              "#{result.queries.size} batch(es) timed out. Run manually:"
            )
            result.queries.each { |q| Rails.logger.warn(q) }
          end
        rescue => e
          duplicate_count = 0
          Rails.logger.error("events:deduplicate_enriched_expanded - Subscription #{subscription.external_id}: Error removing duplicates: #{e.message}")
        end
      end

      total_duplicates += duplicate_count
    end

    mode = dry_run ? "DRY RUN" : "LIVE"
    action = dry_run ? "found" : "removed"
    Rails.logger.info("events:deduplicate_enriched_expanded [#{mode}] - Complete. #{total_duplicates} total duplicate rows #{action}.")
  end

  desc "Detect and optionally reprocess events for subscriptions needing re-enrichment"
  task reprocess: :environment do
    Rails.logger.level = Logger::Severity::INFO

    organization_id = ENV.fetch("ORGANIZATION_ID")
    reprocess = ENV.fetch("REPROCESS", "false") == "true"
    batch_size = (ENV["BATCH_SIZE"] || 1000).to_i
    sleep_seconds = (ENV["SLEEP_SECONDS"] || 0.5).to_f

    organization = Organization.find(organization_id)

    service_result = Events::Stores::Clickhouse::PreEnrichmentCheckService.call(
      organization:, reprocess:, batch_size:, sleep_seconds:
    )

    subscriptions_map = service_result.subscriptions_to_reprocess
    mode = reprocess ? "REPROCESS" : "DRY RUN"

    if subscriptions_map.empty?
      Rails.logger.info("events:reprocess [#{mode}] - No subscriptions need reprocessing")
    else
      subscriptions_map.each do |sub_id, codes|
        Rails.logger.info("events:reprocess [#{mode}] - Subscription #{sub_id}: #{codes.join(", ")}")
      end
      Rails.logger.info("events:reprocess [#{mode}] - #{subscriptions_map.size} subscriptions detected")
    end
  ensure
    Karafka.producer.close if reprocess
  end

  # Recovers pay-in-advance fees for events that were persisted but never post-processed, because
  # Kafka or Redis was down when they were ingested. Only the fee is recovered.
  #
  # Beware: on an invoiceable charge the replay also finalizes an invoice dated at the event
  # timestamp, emails it and starts a payment. The dry-run report says how many are affected.
  #
  # Usage:
  #   lago exec api bundle exec rails events:recover_pay_in_advance_fees \
  #     ORGANIZATION_ID=<uuid> FROM=2026-08-22T00:00:00Z TO=2026-08-24T00:00:00Z [DRY_RUN=false]
  #
  # FROM/TO bound the event ingestion time, as [FROM, TO). DRY_RUN defaults to true (report only).
  desc "Recover pay-in-advance fees for events that were never post-processed"
  task recover_pay_in_advance_fees: :environment do
    prefix = "events:recover_pay_in_advance_fees"
    batch_size = (ENV["BATCH_SIZE"] || 1000).to_i
    organization = Organization.find(ENV.fetch("ORGANIZATION_ID"))
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"

    # `Time.zone.parse` returns nil rather than raising on input it cannot make sense of, and a nil
    # bound silently drops the predicate: the run would then replay the whole event history.
    from = Time.zone.parse(ENV.fetch("FROM")) or raise(ArgumentError, "FROM is not a parsable datetime")
    to = Time.zone.parse(ENV.fetch("TO")) or raise(ArgumentError, "TO is not a parsable datetime")
    raise ArgumentError, "FROM must be earlier than TO" unless from < to
    raise ArgumentError, "BATCH_SIZE must be positive" unless batch_size.positive?

    if organization.clickhouse_events_store?
      puts "#{prefix} - Organization #{organization.id} uses the Clickhouse events store: " \
        "events are not persisted in Postgres, so there is nothing to recover."
      next
    end

    # `Charge belongs_to :billable_metric, -> { with_discarded }`, so the join carries no
    # `deleted_at` predicate: a charge whose metric was discarded would be reported as recoverable
    # while the replay creates nothing, because `Events::Common#billable_metric` resolves nothing.
    # Discarded *plans* are deliberately kept: `Plans::DestroyService` does not discard the charges,
    # so those events are still recoverable.
    charges_by_plan_and_code = Charge.pay_in_advance
      .where(organization_id: organization.id)
      .joins(:billable_metric)
      .where(billable_metrics: {deleted_at: nil})
      .includes(:billable_metric)
      .group_by { |charge| [charge.plan_id, charge.billable_metric.code] }

    if charges_by_plan_and_code.empty?
      puts "#{prefix} - Organization #{organization.id} has no pay-in-advance charge."
      next
    end

    codes = charges_by_plan_and_code.keys.map(&:last).uniq

    # Not narrowed on subscription external ids: that would bind one parameter per subscription, and
    # the per-event lookup below discards those events anyway.
    scope = organization.events.where(created_at: from...to, code: codes)

    recovered = 0
    invoices_to_create = 0
    not_due = 0
    scanned = 0
    skipped = []
    tainted_subscriptions = Set.new
    started_at = Time.current
    total = scope.count

    puts "#{prefix} [#{mode}]"
    puts "Organization: #{organization.id}"
    puts "Ingested in:  [#{from.iso8601}, #{to.iso8601})"
    puts "Candidates:   #{total} event(s) on #{codes.size} pay-in-advance metric code(s)"
    puts "=" * 80

    # Cursored on (created_at, id) so the scan follows index_events_on_organization_id_and_created_at.
    # The default primary-key cursor would paginate on a random uuid, re-sorting the whole remaining
    # window on every batch.
    scope.in_batches(of: batch_size, cursor: [:created_at, :id], order: :asc, load: true) do |events_in_batch|
      # Printed every batch so a long run is visibly progressing rather than possibly stuck.
      scanned += events_in_batch.size
      puts "  ... #{scanned}/#{total} scanned in #{(Time.current - started_at).round(1)}s, " \
        "at #{events_in_batch.last.created_at.iso8601}, #{recovered} to recover, #{skipped.size} skipped"

      # `group_by` preserves the SQL order, so `covering.first` below is what
      # `Events::Common#subscription` resolves to.
      subscriptions_by_external_id = organization.subscriptions
        .where(external_id: events_in_batch.map(&:external_subscription_id).uniq)
        .order(Arel.sql("terminated_at DESC NULLS FIRST, started_at DESC"))
        .group_by(&:external_id)

      candidates = events_in_batch.filter_map do |event|
        covering = subscriptions_by_external_id.fetch(event.external_subscription_id, []).select do |candidate|
          # `started_at` is nil until activation, and NULLS FIRST sorts those first. SQL drops them
          # because the comparison is NULL; the same has to happen here.
          next false if candidate.started_at.nil?

          candidate.started_at.floor(3) <= event.timestamp &&
            (candidate.terminated_at.nil? || candidate.terminated_at.floor(3) >= event.timestamp)
        end

        # Two resolutions disagree in production and both matter: the gate in
        # `Events::PostProcessService#subscriptions` excludes incomplete subscriptions and decides
        # whether a fee is created at all, while `Events::Common#subscription` ignores status and
        # decides which plan's charges the replay bills.
        replayed = covering.first
        eligible = covering.find { |candidate| !candidate.incomplete? }

        if eligible.nil?
          reason = if replayed
            "its only subscriptions are incomplete, which `Events::PostProcessService` skips, " \
              "so no fee was created at ingestion either"
          else
            "no subscription covers its timestamp; a replay would create no fee"
          end
          skipped << [event.transaction_id, event.external_subscription_id, reason]
          next
        end

        if replayed != eligible
          skipped << [event.transaction_id, event.external_subscription_id,
            "the subscription the replay would bill (#{replayed.id}) is not the one post-processing " \
            "would have used (#{eligible.id}); recover it by hand"]
          next
        end

        charges = charges_by_plan_and_code[[eligible.plan_id, event.code]]
        if charges.blank?
          not_due += 1
          next
        end

        # The replay bills whatever the plan carries now, so a charge added after the event was
        # ingested would be billed for a period it did not cover.
        if charges.any? { |charge| charge.created_at > event.created_at }
          skipped << [event.transaction_id, event.external_subscription_id,
            "its plan gained a pay-in-advance charge after the event was ingested, so a replay " \
            "would bill more than the original would have"]
          next
        end

        billable_metric = charges.first.billable_metric
        unless billable_metric.count_agg? ||
            billable_metric.custom_agg? ||
            event.properties[billable_metric.field_name].present?
          not_due += 1
          next
        end

        subscription = eligible

        [event, subscription, charges, billable_metric]
      end
      next if candidates.empty?

      transaction_ids = candidates.map { |event, _, _, _| event.transaction_id }

      # No invoice_id filter: `Fee.from_organization_pay_in_advance` scopes to `invoice_id: nil` and
      # would miss fees already billed.
      charged_ids_by_transaction_id = Fee
        .where(
          organization_id: organization.id,
          pay_in_advance: true,
          original_fee_id: nil,
          pay_in_advance_event_transaction_id: transaction_ids
        )
        .pluck(:pay_in_advance_event_transaction_id, :charge_id)
        .group_by(&:first)
        .transform_values { |rows| rows.map(&:last) }

      # Every index on `pay_in_advance_event_transaction_id` is partial on `deleted_at IS NULL`, so
      # including discarded fees in the query above would make all of them unusable.
      uncharged = transaction_ids - charged_ids_by_transaction_id.keys
      discarded_transaction_ids = if uncharged.empty?
        Set.new
      else
        Fee.with_discarded
          .where.not(deleted_at: nil)
          .where(
            organization_id: organization.id,
            pay_in_advance: true,
            original_fee_id: nil,
            pay_in_advance_event_transaction_id: uncharged
          )
          .distinct
          .pluck(:pay_in_advance_event_transaction_id)
          .to_set
      end

      candidates.each do |event, subscription, charges, billable_metric|
        charged_ids = charged_ids_by_transaction_id[event.transaction_id]

        if charged_ids.present?
          missing = charges.map(&:id) - charged_ids
          if missing.any?
            skipped << [event.transaction_id, event.external_subscription_id,
              "charges #{missing.join(", ")} have no fee while others do, and " \
              "`Events::PayInAdvanceService` skips the whole event once any fee exists"]
          end
          next
        end

        # The guard indexes ignore discarded rows, so a fee that was voided on purpose would look
        # exactly like a missing one.
        if discarded_transaction_ids.include?(event.transaction_id)
          skipped << [event.transaction_id, event.external_subscription_id,
            "its fees are all discarded, so they were either voided on purpose or already " \
            "regenerated; check before recovering it by hand"]
          next
        end

        # `Events::PayInAdvanceService` enqueues one `Invoices::CreatePayInAdvanceChargeJob` per
        # invoiceable charge, and each mints its own invoice, so the blast radius is a count of
        # charges rather than of events.
        invoiceable_charges = charges.count(&:invoiceable?)
        recovered += 1
        invoices_to_create += invoiceable_charges
        tainted_subscriptions << subscription.id unless billable_metric.count_agg?

        puts "  RECOVER #{event.transaction_id} subscription=#{event.external_subscription_id} " \
          "code=#{event.code} invoiceable_charges=#{invoiceable_charges}"

        Events::PayInAdvanceJob.perform_later(Events::CommonFactory.new_instance(source: event).as_json) unless dry_run
      end
    end

    skipped.each do |transaction_id, external_subscription_id, reason|
      puts "  SKIPPED #{transaction_id} (subscription=#{external_subscription_id}): #{reason}."
    end

    puts "=" * 80
    puts "#{recovered} event(s) to recover, #{skipped.size} skipped, #{not_due} with no fee due " \
      "(#{scanned} scanned in #{(Time.current - started_at).round(1)}s)"

    if tainted_subscriptions.any?
      puts
      puts "WARNING: recovered events on subscriptions #{tainted_subscriptions.to_a.join(", ")} use an " \
        "aggregation other than count_agg, so their units chain through cached aggregations. Where " \
        "those billing periods contain decrements, the fees created for the events that followed the " \
        "gap were computed without the missing rows and may over-bill. This task does not fix " \
        "already-created fees."
    end

    if invoices_to_create.positive?
      puts
      puts "WARNING: the replay creates #{invoices_to_create} invoice(s), one per invoiceable charge. " \
        "Each is finalized and dated at the event timestamp, emailed, pushed to the accounting " \
        "integrations, and has a payment started for it."
    end

    if dry_run && recovered.positive?
      puts
      puts "Run again with DRY_RUN=false to re-enqueue."
    end
  end
end
