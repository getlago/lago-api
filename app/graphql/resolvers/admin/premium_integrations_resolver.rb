# frozen_string_literal: true

module Resolvers
  module Admin
    class PremiumIntegrationsResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Lists every premium integration and whether the current staff user may toggle it"

      type [Types::Admin::PremiumIntegrationType], null: false

      Item = Struct.new(:name, :allowed_for_current_user, keyword_init: true)

      def resolve
        role = current_admin_user.role
        allowed = ::Admin::PremiumIntegrations::ToggleService::ROLE_ALLOWED_INTEGRATIONS[role]
        allowed_set = (allowed == :all) ? ::Organization::PREMIUM_INTEGRATIONS : Array(allowed)

        ::Organization::PREMIUM_INTEGRATIONS.map do |name|
          Item.new(name: name, allowed_for_current_user: allowed_set.include?(name))
        end
      end
    end
  end
end
