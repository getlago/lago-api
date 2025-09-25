# frozen_string_literal: true

module Api
  module V1
    class WalletsController < Api::BaseController
      include WalletIndex

      def create
        result = Wallets::CreateService.call(
          params: input_params
            .merge(organization_id: current_organization.id)
            .merge(customer:).to_h.deep_symbolize_keys
        )

        if result.success?
          render_wallet(result.wallet)
        else
          render_error_response(result)
        end
      end

      def update
        result = Wallets::UpdateService.call(
          wallet: current_organization.wallets.find_by(id: params[:id]),
          params: update_params.merge(id: params[:id]).to_h.deep_symbolize_keys
        )

        if result.success?
          render_wallet(result.wallet)
        else
          render_error_response(result)
        end
      end

      def terminate
        wallet = current_organization.wallets.find_by(id: params[:id])
        result = Wallets::TerminateService.call(wallet:)

        if result.success?
          render_wallet(result.wallet)
        else
          render_error_response(result)
        end
      end

      def show
        wallet = current_organization.wallets.find_by(
          id: params[:id]
        )

        return not_found_error(resource: "wallet") unless wallet

        render_wallet(wallet)
      end

      def index
        permitted_params = params.permit(:external_customer_id)
        external_customer_id = permitted_params[:external_customer_id]

        wallet_index(external_customer_id:)
      end

      private

      def input_params
        params.require(:wallet).permit(
          :rate_amount,
          :name,
          :priority,
          :currency,
          :paid_credits,
          :granted_credits,
          :expiration_at,
          :invoice_requires_successful_payment,
          :paid_top_up_min_amount_cents,
          :paid_top_up_max_amount_cents,
          :ignore_paid_top_up_limits_on_creation,
          :transaction_name,
          transaction_metadata: [
            :key,
            :value
          ],
          recurring_transaction_rules: [
            :granted_credits,
            :interval,
            :method,
            :paid_credits,
            :started_at,
            :expiration_at,
            :target_ongoing_balance,
            :threshold_credits,
            :trigger,
            :invoice_requires_successful_payment,
            :ignore_paid_top_up_limits,
            :transaction_name,
            transaction_metadata: [
              :key,
              :value
            ]
          ],
          applies_to: [
            fee_types: [],
            billable_metric_codes: []
          ]
        )
      end

      def customer_params
        params.require(:wallet).permit(:external_customer_id)
      end

      def update_params
        params.require(:wallet).permit(
          :name,
          :priority,
          :expiration_at,
          :invoice_requires_successful_payment,
          :paid_top_up_min_amount_cents,
          :paid_top_up_max_amount_cents,
          recurring_transaction_rules: [
            :lago_id,
            :interval,
            :method,
            :started_at,
            :expiration_at,
            :target_ongoing_balance,
            :threshold_credits,
            :trigger,
            :paid_credits,
            :granted_credits,
            :invoice_requires_successful_payment,
            :ignore_paid_top_up_limits,
            :transaction_name,
            transaction_metadata: [
              :key,
              :value
            ]
          ],
          applies_to: [
            fee_types: [],
            billable_metric_codes: []
          ]
        )
      end

      def customer
        Customer.find_by(external_id: customer_params[:external_customer_id], organization_id: current_organization.id)
      end

      def render_wallet(wallet)
        render(
          json: ::V1::WalletSerializer.new(
            wallet,
            root_name: "wallet",
            includes: %i[recurring_transaction_rules limitations]
          )
        )
      end

      def resource_name
        "wallet"
      end
    end
  end
end
