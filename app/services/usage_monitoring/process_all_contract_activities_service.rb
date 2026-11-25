# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllContractActivitiesService < BaseService
    Result = BaseResult

    def call
      scope = ContractActivity.where(enqueued: false)

      # Clock::ProcessDedicatedOrgsSubscriptionActivitiesJob sweeps the dedicated organizations
      dedicated_org_ids = Utils::DedicatedWorkerConfig.organization_ids
      scope = scope.where.not(organization_id: dedicated_org_ids) if dedicated_org_ids.any?

      scope.distinct.pluck(:organization_id).each do |organization_id|
        ProcessOrganizationContractActivitiesJob.perform_later(organization_id)
      end

      result
    end
  end
end
