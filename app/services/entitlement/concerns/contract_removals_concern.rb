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

      def discard_contract_privilege_removals(organization_id, privilege_ids)
        now = Time.current
        contract_removals(organization_id)
          .where(entitlement_privilege_id: privilege_ids)
          .update_all(deleted_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
