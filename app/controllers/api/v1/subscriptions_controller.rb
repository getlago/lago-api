# frozen_string_literal: true

module Api
  module V1
    class SubscriptionsController < Api::BaseController
      def create
        response = {}

        customer = Customer.find_or_initialize_by(
          external_id: create_params[:external_customer_id].to_s.strip,
          organization_id: current_organization.id
        )

        if params[:authorization] && !current_organization.beta_payment_authorization_enabled?
          return render(
            json: {
              status: 403,
              error: "Forbidden",
              code: "feature_not_available",
              message: "Payment authorization (beta_payment_authorization) is not available for this organization"
            },
            status: :forbidden
          )
        end

        if params[:authorization]
          unless customer.payment_provider&.to_sym == :stripe
            return render(
              json: {
                status: 422,
                error: "Unprocessable Entity",
                code: "stripe_required",
                message: "Only Stripe is supported for authorization"
              },
              status: :unprocessable_entity
            )
          end

          result = PaymentProviders::Stripe::Payments::AuthorizeService.call(
            amount: params[:authorization][:amount],
            currency: params[:authorization][:currency],
            provider_customer: customer.provider_customer,
            metadata: {plan_code: create_params[:plan_code]},
            unique_id: request.request_id
          )

          if result.success?
            response[:authorization] = result.stripe_payment_intent.to_hash.slice(
              :id, :object, :amount, :amount_capturable, :status
            )
          else
            return render_error_response(result)
          end
        end

        plan = Plan.parents.find_by(
          code: create_params[:plan_code],
          organization_id: current_organization.id
        )

        result = Subscriptions::CreateService.call(
          customer:,
          plan:,
          params: create_params.to_h
        )

        if result.success?
          response[:subscription] = ::V1::SubscriptionSerializer.new(
            result.subscription, includes: %i[plan]
          ).serialize

          render(json: response)
        else
          render_error_response(result)
        end
      end

      # NOTE: We can't destroy a subscription, it will terminate it
      def terminate
        query = current_organization.subscriptions.where(external_id: params[:external_id])
        subscription = if params[:status] == "pending"
          query.pending
        else
          query.active
        end.first

        result = Subscriptions::TerminateService.call(subscription:)

        if result.success?
          render_subscription(result.subscription)
        else
          render_error_response(result)
        end
      end

      def update
        query = current_organization.subscriptions
          .where(external_id: params[:external_id])
          .order(subscription_at: :desc)
        subscription = if query.count > 1
          if params[:status] == "pending"
            query.pending
          else
            query.active
          end
        else
          query
        end.first

        result = Subscriptions::UpdateService.call(
          subscription:,
          params: update_params.to_h
        )

        if result.success?
          render_subscription(result.subscription)
        else
          render_error_response(result)
        end
      end

      def show
        subscription = current_organization.subscriptions.find_by(
          external_id: params[:external_id],
          status: params[:status] || :active
        )
        return not_found_error(resource: "subscription") unless subscription

        render_subscription(subscription)
      end

      def index
        result = SubscriptionsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: index_filters
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscriptions,
              ::V1::SubscriptionSerializer,
              collection_name: "subscriptions",
              meta: pagination_metadata(result.subscriptions)
            )
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
            :ending_at,
            plan_overrides:
          )
      end

      def update_params
        params.require(:subscription).permit(
          :name,
          :subscription_date,
          :subscription_at,
          :ending_at,
          plan_overrides:
        )
      end

      def plan_overrides
        [
          :amount_cents,
          :amount_currency,
          :description,
          :name,
          :invoice_display_name,
          :trial_period,
          {tax_codes: []},
          {
            minimum_commitment: [
              :id,
              :invoice_display_name,
              :amount_cents,
              {tax_codes: []}
            ],
            charges: [
              :id,
              :billable_metric_id,
              :min_amount_cents,
              :invoice_display_name,
              :charge_model,
              {properties: {}},
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
          }
        ]
      end

      def index_filters
        params.permit(:external_customer_id, :plan_code, status: [])
      end

      def render_subscription(subscription)
        render(
          json: ::V1::SubscriptionSerializer.new(
            subscription,
            root_name: "subscription",
            includes: %i[plan]
          )
        )
      end

      def resource_name
        "subscription"
      end
    end
  end
end
