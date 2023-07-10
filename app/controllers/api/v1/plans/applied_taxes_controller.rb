# frozen_string_literal: true

module Api
  module V1
    module Plans
      class AppliedTaxesController < Api::BaseController
        def create
          tax = current_organization.taxes.find_by(code: input_params[:tax_code])
          result = ::Plans::AppliedTaxes::CreateService.call(plan:, tax:)
          if result.success?
            render(json: ::V1::Plans::AppliedTaxSerializer.new(result.applied_tax, root_name: 'applied_tax'))
          else
            render_error_response(result)
          end
        end

        def destroy
          tax = current_organization.taxes.find_by(code: params[:tax_code])
          applied_tax = Plan::AppliedTax.find_by(plan:, tax:)
          result = ::Plans::AppliedTaxes::DestroyService.call(applied_tax:)
          if result.success?
            render(json: ::V1::Plans::AppliedTaxSerializer.new(result.applied_tax, root_name: 'applied_tax'))
          else
            render_error_response(result)
          end
        end

        private

        def plan
          @plan ||= current_organization.plans.find_by(code: params[:plan_code])
        end

        def input_params
          params.require(:applied_tax).permit(:tax_code)
        end
      end
    end
  end
end
