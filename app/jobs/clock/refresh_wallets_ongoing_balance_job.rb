# frozen_string_literal: true

module Clock
  class RefreshWalletsOngoingBalanceJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform(organization: nil)
      return unless License.premium?

      wallets = Wallet.active.ready_to_be_refreshed

      if organization
        wallets = wallets.where(organization_id: organization.id)
      else
        excluded_organization_ids = JobScheduleOverride
          .enabled
          .where(job_name: self.class.name)
          .pluck(:organization_id)

        wallets = wallets.where.not(organization_id: excluded_organization_ids) if excluded_organization_ids.any?
      end

      wallets.find_each do |wallet|
        Wallets::RefreshOngoingBalanceJob.perform_later(wallet)
      end
    end
  end
end
