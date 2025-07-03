# frozen_string_literal: true

module Api
  module V1
    class WalletsController < Api::BaseController
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
        result = WalletsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {external_customer_id: params[:external_customer_id]}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.wallets.includes(:recurring_transaction_rules),
              ::V1::WalletSerializer,
              collection_name: "wallets",
              meta: pagination_metadata(result.wallets),
              includes: %i[recurring_transaction_rules]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.expect(
          wallet: [
            :rate_amount,
            :name,
            :currency,
            :paid_credits,
            :granted_credits,
            :expiration_at,
            :invoice_requires_successful_payment,
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
              transaction_metadata: [
                :key,
                :value
              ]
            ],
            applies_to: [
              fee_types: []
            ]
          ]
        )
      end

      def customer_params
        params.expect(wallet: [:external_customer_id])
      end

      def update_params
        params.expect(
          wallet: [
            :name,
            :expiration_at,
            :invoice_requires_successful_payment,
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
              transaction_metadata: [
                :key,
                :value
              ]
            ],
            applies_to: [
              fee_types: []
            ]
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
