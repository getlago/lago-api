# frozen_string_literal: true

module Api
  module V1
    class PlansController < Api::BaseController
      def create
        service = Plans::CreateService.new
        result = service.create(
          **input_params
            .merge(organization_id: current_organization.id)
            .to_h
            .deep_symbolize_keys,
        )

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def update
        plan = current_organization.plans.find_by(code: params[:code])
        result = Plans::UpdateService.call(plan:, params: input_params)

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def destroy
        plan = current_organization.plans.find_by(code: params[:code])
        result = Plans::PrepareDestroyService.call(plan:)

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def show
        plan = current_organization.plans.find_by(
          code: params[:code],
        )

        return not_found_error(resource: 'plan') unless plan

        render_plan(plan)
      end

      def index
        plans = current_organization.plans
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            plans,
            ::V1::PlanSerializer,
            collection_name: 'plans',
            meta: pagination_metadata(plans),
            includes: %i[charges],
          ),
        )
      end

      private

      def input_params
        params.require(:plan).permit(
          :name,
          :code,
          :interval,
          :description,
          :amount_cents,
          :amount_currency,
          :trial_period,
          :pay_in_advance,
          :bill_charges_monthly,
          charges: [
            :id,
            :billable_metric_id,
            :charge_model,
            { properties: {} },
            group_properties: [
              :group_id,
              { values: {} },
            ],
          ],
        )
      end

      def render_plan(plan)
        render(
          json: ::V1::PlanSerializer.new(
            plan,
            root_name: 'plan',
            includes: %i[charges],
          ),
        )
      end
    end
  end
end
