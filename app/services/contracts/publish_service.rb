# frozen_string_literal: true

module Contracts
  # Releases a draft for billing, the only way out of draft. A draft whose start
  # is still ahead becomes pending and the clock starts it; one whose start has
  # passed is activated now, which catches up the periods elapsed since the start.
  # Publishing again sends nothing, so a retry is safe; a retry once the start
  # has passed activates the contract, as the first publication would have.
  class PublishService < BaseService
    Result = BaseResult[:contract]

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      ActiveRecord::Base.transaction do
        # The clock's lock first, then the row, as activation and termination take them.
        Customers::LockService.call!(customer: contract.customer, scope: :billing_schedule) do
          # Re-read under lock: a concurrent publish or cancellation may have won.
          contract.lock!

          if contract.pending? || contract.active?
            # ActivateService does nothing unless the contract is pending and its start has passed.
            Contracts::ActivateService.call!(contract:) if contract.pending?
            result.contract = contract
            next
          end

          unless contract.draft?
            result.single_validation_failure!(field: :contract, error_code: "cannot_publish").raise_if_error!
          end

          # Without a start the clock would never activate it.
          if contract.started_at.blank?
            result.single_validation_failure!(field: :started_at, error_code: "value_is_mandatory").raise_if_error!
          end

          if contract.ended_at.present? && contract.ended_at <= Time.current
            result.single_validation_failure!(field: :ended_at, error_code: "already_ended").raise_if_error!
          end

          # Activation needs a kept customer: the contract would stay pending forever.
          unless contract.customer.kept?
            result.single_validation_failure!(field: :customer, error_code: "customer_deleted").raise_if_error!
          end

          # Create refuses a live sibling, but two concurrent creates can still commit
          # one, as the unique index is per status.
          if (sibling_status = live_sibling_status)
            error_code = (sibling_status == "active") ? "active_contract_exists" : "value_already_exists"
            result.single_validation_failure!(field: :external_id, error_code:).raise_if_error!
          end

          # Its own event, as every other lifecycle step has: contract.updated could not tell a
          # publication from an edit. Like contract.created, it renders the contract after commit,
          # so a publication that activates sends it active, before contract.started.
          contract.update!(status: :pending)
          SendWebhookJob.perform_after_commit("contract.published", contract)
          Utils::ActivityLog.produce_after_commit(contract, "contract.published")

          # Inside the transaction, so an activation that fails rolls back the move to pending.
          # As on create, a contract without cards or with unpriced cards goes active:
          # ActivateService skips a card it cannot schedule.
          if contract.started_at <= Time.current
            published_at = Time.current
            Contracts::ActivateService.call!(contract:, timestamp: published_at)
            # Usage priced in advance skipped the draft: bill what arrived since its start. Delayed
            # past the ClickHouse merge, so the events sent right before the publication are read.
            if contract.active?
              AfterCommitEverywhere.after_commit do
                Contracts::ReplayDraftUsageJob.set(wait: Events::Stores::ClickhouseStore::CLICKHOUSE_MERGE_DELAY)
                  .perform_later(contract, published_at)
              end
            end
          end

          result.contract = contract
        end
      end

      result
    rescue ActiveRecord::RecordNotUnique => e
      # Not unique_index_failure!, whose value_already_exist differs from what create answers for this index.
      raise unless violated_unique_index(e) == "index_contracts_on_live_external_id"

      result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :contract

    def live_sibling_status
      contract.organization.contracts
        .where(external_id: contract.external_id, status: %w[pending active])
        .where.not(id: contract.id)
        .order(Arel.sql("status = 'active' DESC"))
        .pick(:status)
    end
  end
end
