# frozen_string_literal: true

module UsageMonitoring
  class ProcessContractActivityJob < ApplicationJob
    queue_as do
      Utils::DedicatedWorkerConfig.queue_for(
        ContractActivity.where(id: arguments.first).pick(:organization_id),
        dedicated: Utils::DedicatedWorkerConfig::DEDICATED_ALERTS_QUEUE,
        default: ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"]) ? :alerts : :default
      )
    end

    def perform(contract_activity_id, attempt = 1)
      contract_activity = ContractActivity.find_by(id: contract_activity_id)
      ProcessContractActivityService.call!(contract_activity:) if contract_activity
    rescue => e
      Sentry.capture_exception(e) if defined?(Sentry)
      if attempt > 3
        ContractActivity.where(id: contract_activity_id).delete_all
        raise e
      end
      self.class.perform_later(contract_activity_id, attempt + 1)
    end
  end
end
