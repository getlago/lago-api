# frozen_string_literal: true

module Api
  module V2
    class PlanWalletsController < Api::V2::BaseController
      include Api::RequiresCatalogWallets
      include Api::CatalogWalletParams

      cursor_paginated_index(PlanWallet)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::PlanWalletSerializer

      def create
        result = ::PlanWallets::CreateService.call(catalog_plan: find_catalog_plan, params: plan_wallet_params)

        if result.success?
          render_plan_wallet(result.plan_wallet)
        else
          render_error_response(result)
        end
      end

      def update
        result = ::PlanWallets::UpdateService.call(plan_wallet: find_plan_wallet, params: plan_wallet_params)

        if result.success?
          render_plan_wallet(result.plan_wallet)
        else
          render_error_response(result)
        end
      end

      def destroy
        result = ::PlanWallets::DestroyService.call(plan_wallet: find_plan_wallet)

        if result.success?
          render_plan_wallet(result.plan_wallet)
        else
          render_error_response(result)
        end
      end

      def show
        plan_wallet = find_plan_wallet

        return not_found_error(resource: "plan_wallet") unless plan_wallet

        render_plan_wallet(plan_wallet)
      end

      def index
        return not_found_error(resource: "plan") unless find_catalog_plan

        result = ::PlanWalletsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: {plan_id: find_catalog_plan.id, **date_range_filters}
        )

        if result.success?
          render_plan_wallets(result.plan_wallets.preload(::V2::PlanWalletSerializer::PRELOADS))
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

      def find_plan_wallet
        plan_wallets&.find_by(code: params[:code])
      end

      def plan_wallet_params
        catalog_wallet_params(:plan_wallet)
      end

      def resource_name
        "plan_wallet"
      end
    end
  end
end
