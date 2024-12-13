# frozen_string_literal: true

module Api
  module V1
    class PlansController < Api::BaseController
      def create
        result = ::Plans::CreateService.call(
          input_params.merge(organization_id: current_organization.id).to_h.deep_symbolize_keys
        )

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def update
        plan = current_organization.plans.parents.find_by(code: params[:code])
        result = ::Plans::UpdateService.call(plan:, params: input_params.to_h.deep_symbolize_keys)

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def destroy
        plan = current_organization.plans.parents.find_by(code: params[:code])
        result = ::Plans::PrepareDestroyService.call(plan:)

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def show
        plan = current_organization.plans.parents
          .includes(:usage_thresholds, charges: {filters: {values: :billable_metric_filter}})
          .find_by(code: params[:code])
        return not_found_error(resource: 'plan') unless plan

        render_plan(plan)
      end

      def index
        result = PlansQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {include_pending_deletion: true}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.plans.includes(
                :usage_thresholds,
                :taxes,
                :minimum_commitment,
                charges: {filters: {values: :billable_metric_filter}}
              ),
              ::V1::PlanSerializer,
              collection_name: "plans",
              meta: pagination_metadata(result.plans),
              includes: %i[charges usage_thresholds taxes minimum_commitment]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:plan).permit(
          :name,
          :invoice_display_name,
          :code,
          :interval,
          :description,
          :amount_cents,
          :amount_currency,
          :trial_period,
          :pay_in_advance,
          :bill_charges_monthly,
          :cascade_updates,
          tax_codes: [],
          minimum_commitment: [
            :id,
            :invoice_display_name,
            :amount_cents,
            {tax_codes: []}
          ],
          charges: [
            :id,
            :invoice_display_name,
            :billable_metric_id,
            :charge_model,
            :pay_in_advance,
            :prorated,
            :invoiceable,
            :regroup_paid_fees,
            :min_amount_cents,
            {
              properties: {}
            },
            {
              filters: [
                :invoice_display_name,
                {
                  properties: {},
                  values: {}
                }
              ]
            },
            {tax_codes: []}
          ],
          usage_thresholds: [
            :id,
            :threshold_display_name,
            :amount_cents,
            :recurring
          ]
        )
      end

      def render_plan(plan)
        render(
          json: ::V1::PlanSerializer.new(
            plan,
            root_name: 'plan',
            includes: %i[charges usage_thresholds taxes minimum_commitment]
          )
        )
      end

      def resource_name
        'plan'
      end
    end
  end
end
