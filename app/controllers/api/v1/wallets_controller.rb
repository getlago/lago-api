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

        return not_found_error(resource: 'wallet') unless wallet

        render_wallet(wallet)
      end

      def index
        customer = current_organization.customers.find_by(external_id: params[:external_customer_id])
        return not_found_error(resource: 'customer') unless customer

        wallets = customer.wallets
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            wallets,
            ::V1::WalletSerializer,
            collection_name: 'wallets',
            meta: pagination_metadata(wallets),
            includes: %i[recurring_transaction_rules]
          )
        )
      end

      private

      def input_params
        params.require(:wallet).permit(
          :rate_amount,
          :name,
          :currency,
          :paid_credits,
          :granted_credits,
          :expiration_at,
          recurring_transaction_rules: [
            :granted_credits,
            :interval,
            :method,
            :paid_credits,
            :started_at,
            :target_ongoing_balance,
            :threshold_credits,
            :trigger
          ]
        )
      end

      def customer_params
        params.require(:wallet).permit(:external_customer_id)
      end

      def update_params
        params.require(:wallet).permit(
          :name,
          :expiration_at,
          recurring_transaction_rules: [
            :lago_id,
            :interval,
            :method,
            :started_at,
            :target_ongoing_balance,
            :threshold_credits,
            :trigger,
            :paid_credits,
            :granted_credits
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
            root_name: 'wallet',
            includes: %i[recurring_transaction_rules]
          )
        )
      end
    end
  end
end
