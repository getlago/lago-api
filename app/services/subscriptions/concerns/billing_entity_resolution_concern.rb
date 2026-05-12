# frozen_string_literal: true

module Subscriptions
  module Concerns
    module BillingEntityResolutionConcern
      extend ActiveSupport::Concern

      private

      def resolve_billing_entity(customer:, params:, fallback_id: nil)
        if customer.organization.feature_flag_enabled?(:multi_entity_billing)
          attrs = if params[:billing_entity_id].present?
            {id: params[:billing_entity_id]}
          elsif params[:billing_entity_code].present?
            {code: params[:billing_entity_code]}
          end

          return customer.organization.billing_entities.find_by!(attrs) if attrs
        end

        fallback_id && customer.organization.billing_entities.find_by(id: fallback_id)
      rescue ActiveRecord::RecordNotFound
        result.not_found_failure!(resource: "billing_entity").raise_if_error!
      end
    end
  end
end
