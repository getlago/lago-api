# frozen_string_literal: true

module Contracts
  # Starts a pending contract once its start has arrived and schedules its
  # first billing. A pending contract with an active sibling on the same
  # external id is a replacement whose predecessor should have been ended by
  # the handover: activation fails rather than leave it waiting unnoticed.
  class ActivateService < BaseService
    Result = BaseResult[:contract]

    def initialize(contract:, timestamp: Time.current)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      ActiveRecord::Base.transaction do
        Customers::LockService.call!(customer: contract.customer, scope: :billing_schedule) do
          # Re-read under lock: a contract canceled since it was loaded stays canceled.
          contract.lock!
          next unless due?

          if active_sibling?
            return result.single_validation_failure!(field: :external_id, error_code: "active_contract_exists")
          end

          # Card and phase edits lock the card, then read the contract: holding the
          # cards makes an edit in flight finish first, and a later one see the activation.
          contract.applied_rate_cards.lock.pluck(:id)
          reseed_stale_rate_cards

          contract.update!(status: :active)
          schedule_initial_billing
          SendWebhookJob.perform_after_commit("contract.started", contract)
          Utils::ActivityLog.produce_after_commit(contract, "contract.started")
        end
      end

      result.contract = contract
      result
    rescue ActiveRecord::RecordNotUnique => e
      # An active sibling committed after the check; same answer as the check.
      raise unless e.message.include?("index_contracts_on_live_external_id")

      result.single_validation_failure!(field: :external_id, error_code: "active_contract_exists")
    rescue BaseService::FailedResult => e
      e.result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :contract, :timestamp

    # A customer deleted since the job was enqueued has nothing left to bill.
    def due?
      contract.pending? && contract.started_at.present? && contract.started_at <= timestamp && contract.customer.kept?
    end

    # Cards seeded before a pending contract's start moved still start on the old
    # day, from which billing would invoice periods before the contract started.
    def reseed_stale_rate_cards
      start_day = contract.default_rate_card_lifecycle[:effective_date]

      cards_for_activation.where.not(effective_date: start_day).find_each do |card|
        own_anchor = card.inherited_billing_anchor?(contract.billing_anchor_date) ? nil : card.billing_anchor_date
        ContractRateCards::SeedLifecycleService.call!(contract_rate_card: card, billing_anchor_date: own_anchor)
      end
    end

    # A clock was set from the schedule its card had when seeded; phases and
    # rates edited while the contract was pending can change the cadence since.
    # A card never billed yet waits for its first billing date, so a late
    # activation still bills the periods elapsed since the start.
    def schedule_initial_billing
      created_operation = false
      cards_for_activation.find_each do |card|
        planned_operation = ContractRateCards::ResetBillingClockService.call!(contract_rate_card: card, timestamp:).planned_operation
        next unless planned_operation && planned_operation.billing_at <= timestamp

        BillingOperations::CreateService.call!(
          contract_rate_card: card,
          action_type: card.periodic_billing_action,
          reason: BillingOperation::REASONS.fetch(:contract_activation),
          planned_operation:
        )
        created_operation = true
      end
      BillingOperations::ProcessJob.perform_after_commit(contract.customer_id) if created_operation
    end

    def cards_for_activation
      contract.applied_rate_cards
        .preload(rate_card: [:rates, {product: :billable_metric}], rate_phases: :rate_override)
        .preload(:earliest_pending_periodic_operation, :latest_completed_periodic_operation)
    end

    def active_sibling?
      Contract.active.exists?(organization_id: contract.organization_id, external_id: contract.external_id)
    end
  end
end
