# frozen_string_literal: true

module Api
  module V1
    module Wallets
      class MetadataController < BaseController
        def create
          result = ::Wallets::UpdateService.call(wallet:, params: metadata_params)

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        def update
          result = ::Wallets::UpdateService.call(wallet:, partial_metadata: true, params: metadata_params)

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::Wallets::UpdateService.call(wallet:, params: {metadata: nil})

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        def destroy_key
          return not_found_error(resource: "metadata") unless wallet.metadata

          result = Metadata::DeleteItemKeyService.call(item: wallet.metadata, key: params[:key])

          if result.success?
            render_metadata
          else
            render_error_response(result)
          end
        end

        private

        def metadata_params
          {metadata: params.fetch(:metadata, {}).permit!.to_h}
        end

        def render_metadata
          render(json: {metadata: wallet.reload.metadata&.value})
        end
      end
    end
  end
end
