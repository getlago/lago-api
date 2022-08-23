# frozen_string_literal: true

module Api
  module V1
    class WalletsController < Api::BaseController
      def create
        service = Wallets::CreateService.new
        result = service.create(
          **input_params
            .merge(organization_id: current_organization.id)
            .to_h
            .symbolize_keys
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
          **update_params.merge(id: params[:id])
            .to_h
            .symbolize_keys
        )

        if result.success?
          render_wallet(result.wallet)
        else
          render_error_response(result)
        end
      end

      def terminate
        service = Wallets::TerminateService.new
        result = service.terminate(params[:id])

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

        return not_found_error unless wallet

        render_wallet(wallet)
      end

      def index
        customer = Customer.find_by(customer_id: params[:customer_id])

        return not_found_error unless customer

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
          :customer_id,
          :rate_amount,
          :name,
          :paid_credits,
          :granted_credits,
          :expiration_date,
        )
      end

      def update_params
        params.require(:wallet).permit(
          :name,
          :expiration_date
        )
      end

      def render_wallet(wallet)
        render(
          json: ::V1::WalletSerializer.new(
            wallet,
            root_name: 'wallet',
          ),
        )
      end
    end
  end
end
