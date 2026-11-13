# frozen_string_literal: true

module Api
  module V2
    class PlanWalletsController < Api::V2::BaseController
      include Api::RequiresCatalogWallets

      cursor_paginated_index(PlanWallet)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::PlanWalletSerializer, root: :wallet

      # What a selector renders its target from.
      SELECTOR_TARGETS = [:product_category, :product, {product_filter: :product}].freeze

      def show
        plan_wallet = plan_wallets&.includes(selectors: SELECTOR_TARGETS)&.find_by(code: params[:code])

        return not_found_error(resource: "wallet") unless plan_wallet

        render_wallet(plan_wallet)
      end

      def index
        return not_found_error(resource: "plan") unless find_catalog_plan

        result = ::PlanWalletsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: {plan_id: find_catalog_plan.id, **date_range_filters}
        )

        if result.success?
          render_wallets(
            result.plan_wallets.includes(:catalog_plan, selectors: SELECTOR_TARGETS)
          )
        else
          render_error_response(result)
        end
      end

      private

      def find_catalog_plan
        return @find_catalog_plan if defined?(@find_catalog_plan)

        @find_catalog_plan = current_organization.catalog_plans.find_by(code: params[:plan_code])
      end

      def plan_wallets
        find_catalog_plan&.wallets
      end

      def resource_name
        "plan_wallet"
      end
    end
  end
end
