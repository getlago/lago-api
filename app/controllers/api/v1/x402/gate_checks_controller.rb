# frozen_string_literal: true

module Api
  module V1
    module X402
      class GateChecksController < BaseController
        def create
          result = ::X402::GateChecks::CheckService.call(organization: current_organization, params: create_params.to_h.symbolize_keys)

          if result.success?
            render(json: ::V1::X402::GateCheckSerializer.new(result, root_name: "gate_check"))
          else
            render_error_response(result)
          end
        end

        private

        def create_params
          params.require(:gate_check).permit(
            :connection_code, :wallet_code, :agent_address, :resource, :plan_code,
            :billable_metric_code, :amount_cents, :estimated_call_cost_cents
          )
        end
      end
    end
  end
end
