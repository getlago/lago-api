# frozen_string_literal: true

module Api
  module V1
    class SubscriptionsController < Api::BaseController
      def create
        customer = Customer.find_or_initialize_by(
          external_id: create_params[:external_customer_id].to_s.strip,
          organization_id: current_organization.id,
        )

        plan = Plan.find_by(
          code: create_params[:plan_code],
          organization_id: current_organization.id,
        )

        result = Subscriptions::CreateService.call(
          customer:,
          plan:,
          params: SubscriptionLegacyInput.new(
            current_organization,
            create_params,
          ).create_input,
        )

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
            ),
          )
        else
          render_error_response(result)
        end
      end

      # NOTE: We can't destroy a subscription, it will terminate it
      def terminate
        query = current_organization.subscriptions.where(external_id: params[:external_id])
        subscription = if params[:status] == 'pending'
          query.pending
        else
          query.active
        end.first

        result = Subscriptions::TerminateService.call(subscription:)

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def update
        service = Subscriptions::UpdateService.new

        result = service.update(
          subscription: current_organization.subscriptions.find_by(external_id: params[:external_id]),
          args: SubscriptionLegacyInput.new(
            current_organization,
            update_params,
          ).update_input,
        )

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def index
        result = SubscriptionsQuery.call(
          organization: current_organization,
          pagination: BaseQuery::Pagination.new(
            page: params[:page],
            limit: params[:per_page] || PER_PAGE,
          ),
          filters: BaseQuery::Filters.new(index_filters),
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscriptions,
              ::V1::SubscriptionSerializer,
              collection_name: 'subscriptions',
              meta: pagination_metadata(result.subscriptions),
            ),
          )
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:subscription)
          .permit(
            :external_customer_id,
            :plan_code,
            :name,
            :external_id,
            :billing_time,
            :subscription_date,
            :subscription_at,
          )
      end

      def update_params
        params.require(:subscription).permit(:name, :subscription_date, :subscription_at)
      end

      def index_filters
        params.permit(:external_customer_id, :plan_code, status: [])
      end
    end
  end
end
