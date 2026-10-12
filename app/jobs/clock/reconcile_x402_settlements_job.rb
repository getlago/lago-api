# frozen_string_literal: true

module Clock
  class ReconcileX402SettlementsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 10.minutes

    def perform
      X402::Settlement.pending_reconciliation.find_each do |settlement|
        X402::Settlements::ReconcileJob.perform_later(settlement)
      end
    end
  end
end
