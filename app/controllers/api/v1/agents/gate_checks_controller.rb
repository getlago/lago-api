# frozen_string_literal: true

module Api
  module V1
    module Agents
      class GateChecksController < Api::BaseController
        skip_audit_logs!

        before_action :ensure_agent_storefront_enabled

        def create
          result = ::Agents::GateCheckService.call(
            organization: current_organization,
            params: create_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render(json: ::V1::Agents::GateCheckSerializer.new(result, root_name: "gate_check"))
          else
            render_error_response(result)
          end
        end

        private

        def ensure_agent_storefront_enabled
          forbidden_error(code: "feature_unavailable") unless current_organization.agent_storefront_enabled?
        end

        def create_params
          params.require(:gate_check).permit(:storefront_code, :token, :billable_metric_code, :estimated_call_cost_cents)
        end

        def resource_name
          "agent"
        end
      end
    end
  end
end
