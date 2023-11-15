# frozen_string_literal: true

module Api
  module V1
    class WalletsController < Api::BaseController
      def create
        service = Wallets::CreateService.new
        result = service.create(
          WalletLegacyInput.new(
            current_organization,
            input_params
              .merge(organization_id: current_organization.id)
              .merge(customer:).to_h.deep_symbolize_keys,
          ).create_input,
        )

        if result.success?
          render_wallet(result.wallet)
        else
          render_error_response(result)
        end
      end

      def update
        service = Wallets::UpdateService.new
        result = service.update(
          wallet: current_organization.wallets.find_by(id: params[:id]),
          args: WalletLegacyInput.new(
            current_organization,
            update_params.merge(id: params[:id]).to_h.deep_symbolize_keys,
          ).update_input,
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
          id: params[:id],
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
          ),
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
          # NOTE: Legacy field
          :expiration_date,
          recurring_transaction_rules: [
            :rule_type,
            :interval,
            :threshold_credits,
          ],
        )
      end

      def customer_params
        params.require(:wallet).permit(:external_customer_id)
      end

      def update_params
        params.require(:wallet).permit(
          :name,
          :expiration_at,
          # NOTE: Legacy field
          :expiration_date,
          recurring_transaction_rules: [
            :lago_id,
            :rule_type,
            :interval,
            :threshold_credits,
            :paid_credits,
            :granted_credits,
          ],
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
            includes: %i[recurring_transaction_rules],
          ),
        )
      end
    end
  end
end
