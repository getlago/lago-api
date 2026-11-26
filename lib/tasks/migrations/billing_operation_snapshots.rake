# frozen_string_literal: true

class BillingOperationSnapshotsBackfill
  class UnverifiableOperation < StandardError; end

  def initialize(organization_id: nil, dry_run: true)
    @organization_id = organization_id
    @dry_run = dry_run
  end

  def run
    failures = 0
    organizations = Organization.all
    organizations = organizations.where(id: organization_id) if organization_id.present?
    organizations.find_each do |organization|
      BillingOperation.where(organization:).find_each do |operation|
        Customers::LockService.call!(customer_id: operation.customer_id, scope: :billing_schedule) do
          backfill(operation.reload(lock: true))
        end
      rescue UnverifiableOperation, BaseService::FailedResult, BaseLockService::FailedToAcquireLock => error
        failures += 1
        puts "BLOCKED operation=#{operation.id}: #{error.message}"
      end
    end
    raise UnverifiableOperation, "#{failures} operations require manual review" if failures.positive?
  end

  private

  attr_reader :organization_id, :dry_run

  def backfill(operation)
    rows = BillingOperationSegment.where(organization_id: operation.organization_id, billing_operation_id: operation.id)
    if operation.coverage_started_at && operation.coverage_ended_at && rows.exists?
      puts "SKIP operation=#{operation.id}: already snapshotted"
      return
    end
    if operation.cancelled_at?
      raise UnverifiableOperation, "cancelled operation has no verified snapshot"
    end
    if operation.coverage_started_at || operation.coverage_ended_at || rows.exists?
      raise UnverifiableOperation, "partial snapshot; existing data was not overwritten"
    end
    unless BillingOperation::PERIODIC_ACTIONS.key?(operation.action_type)
      raise UnverifiableOperation, "no historical coverage for reconciliation"
    end

    # Legacy operations were billed from schedule slices rather than saved snapshots.
    segments = BillingOperations::ResolveSegmentsService.call!(operation:).billing_segments
    raise UnverifiableOperation, "legacy resolver returned no coverage" if segments.empty?

    verify_completed_history!(operation, segments) if operation.processed_at?
    attributes = segments.each_with_index.map do |segment, position|
      {
        organization_id: operation.organization_id, billing_operation_id: operation.id, position:,
        rate_card_rate_id: segment.rate_card_rate_id, rate_override_id: segment.rate_override_id,
        started_at: segment.started_at, ended_at: BillingSegment.exclusive_end(segment.ended_at),
        proration_ratio: segment.proration_ratio
      }
    end
    coverage = {
      coverage_started_at: attributes.first.fetch(:started_at),
      coverage_ended_at: attributes.last.fetch(:ended_at)
    }
    puts "#{dry_run ? "DRY RUN" : "BACKFILL"} operation=#{operation.id} #{coverage.inspect} segments=#{attributes.inspect}"
    unless dry_run
      BillingOperationSegment.insert_all!(attributes) # rubocop:disable Rails/SkipsModelValidations
      BillingOperation.where(organization_id: operation.organization_id, id: operation.id)
        .update_all(**coverage, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def verify_completed_history!(operation, segments)
    raise UnverifiableOperation, "completed operation has no invoice to verify" unless operation.invoice_id

    sources = [operation.contract_rate_card.rate_card, *operation.contract_rate_card.rate_phases,
      *segments.flat_map { [it.rate_card_rate, it.rate_override] }.compact]
    if sources.any? { it.updated_at > operation.processed_at }
      raise UnverifiableOperation, "pricing inputs changed after processing"
    end

    fees = Fee.with_discarded.product.where(organization_id: operation.organization_id,
      invoice_id: operation.invoice_id, contract_rate_card_id: operation.contract_rate_card_id)
    billed_slices = fees.map do |fee|
      properties = fee.properties
      from = properties["from_datetime"]
      to = properties["to_datetime"]
      unless from.is_a?(String) && to.is_a?(String)
        raise UnverifiableOperation, "fee coverage is missing"
      end

      [fee.rate_card_rate_id, fee.rate_override_id, Time.iso8601(from), Time.iso8601(to)]
    rescue ArgumentError
      raise UnverifiableOperation, "fee coverage is invalid"
    end.uniq
    resolved_slices = segments.map { [it.rate_card_rate_id, it.rate_override_id, it.started_at, it.ended_at] }
    unless billed_slices.sort_by { it[2] } == resolved_slices.sort_by { it[2] }
      raise UnverifiableOperation, "resolved coverage does not match saved invoice fees"
    end
  end
end

namespace :migrations do
  desc "Snapshot legacy billing operations before deploying saved-segment billing (DRY_RUN=true by default)"
  task billing_operation_snapshots: :environment do
    BillingOperationSnapshotsBackfill.new(
      organization_id: ENV["ORGANIZATION_ID"],
      dry_run: ENV.fetch("DRY_RUN", "true") != "false"
    ).run
  end
end
