# frozen_string_literal: true

module Entitlement
  module Concerns
    # Only contract removals are discarded with a feature or a privilege: subscription removals keep their existing behaviour.
    module ContractRemovalsConcern
      extend ActiveSupport::Concern

      private

      def contract_removals(organization_id)
        SubscriptionFeatureRemoval.where(organization_id:).where.not(contract_id: nil)
      end

      # FOR KEY SHARE waits for a feature or privilege delete in progress, which discards the contract removals, so no
      # removal is stored for a deleted feature. lock! reloads unscoped, hence the discarded? check.
      def lock_feature_for_contract_removal!(feature)
        feature&.lock!("FOR KEY SHARE")
        result.not_found_failure!(resource: "feature").raise_if_error! if feature.nil? || feature.discarded?
      end

      def discard_contract_privilege_removals(organization_id, privilege_ids)
        now = Time.current
        contract_removals(organization_id)
          .where(entitlement_privilege_id: privilege_ids)
          .update_all(deleted_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
