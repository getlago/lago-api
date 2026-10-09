# frozen_string_literal: true

module Api
  module V1
    module X402
      class ConnectionsController < BaseController
        filter_audit_log_params! :cdp_api_key_id, :cdp_api_key_secret

        def create
          result = ::X402::Connections::CreateService.call(
            organization: current_organization,
            params: input_params.to_h
          )

          if result.success?
            render_connection(result.connection)
          else
            render_error_response(result)
          end
        end

        def update
          connection = find_connection
          return not_found_error(resource: "x402_connection") unless connection

          result = ::X402::Connections::UpdateService.call(connection:, params: input_params.to_h)

          if result.success?
            render_connection(result.connection)
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::X402::Connections::DestroyService.call(connection: find_connection)

          if result.success?
            render_connection(result.connection)
          else
            render_error_response(result)
          end
        end

        def show
          connection = find_connection
          return not_found_error(resource: "x402_connection") unless connection

          render_connection(connection)
        end

        def index
          connections = current_organization.x402_connections
            .order(created_at: :desc)
            .order(id: :asc)
            .page(params[:page])
            .per(params[:per_page] || PER_PAGE)

          render(
            json: ::CollectionSerializer.new(
              connections,
              ::V1::X402::ConnectionSerializer,
              collection_name: "x402_connections",
              meta: pagination_metadata(connections)
            )
          )
        end

        private

        def find_connection
          current_organization.x402_connections.find_by(code: params[:code])
        end

        def input_params
          @input_params ||= params.require(:x402_connection).permit(
            :code, :name, :facilitator, :asset, :auto_create_customers, :cdp_api_key_id, :cdp_api_key_secret,
            networks: [], payout_addresses: {}
          )
        end

        def render_connection(connection)
          render(json: ::V1::X402::ConnectionSerializer.new(connection, root_name: "x402_connection"))
        end

        def resource_name
          "x402_connection"
        end
      end
    end
  end
end
