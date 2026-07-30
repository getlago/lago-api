# frozen_string_literal: true

module Api
  module V2
    class SubscriptionsController < Api::BaseController
      include Api::RequiresProductCatalog

      def index
        filters = params.permit(:plan_code, :external_customer_id, :external_id, status: [])
        filters[:status] = ["active"] if filters[:status].blank?

        result = ::SubscriptionsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters:
        )

        if result.success?
          subscriptions = result.subscriptions.includes(:plan, customer: :billing_entity)

          render(
            json: ::CollectionSerializer.new(
              subscriptions,
              ::V2::SubscriptionSerializer,
              collection_name: "subscriptions",
              meta: pagination_metadata(subscriptions)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        subscription = current_organization.subscriptions
          .order("terminated_at DESC NULLS FIRST, started_at DESC")
          .find_by(
            external_id: params[:external_id],
            status: params[:status] || :active
          )
        return not_found_error(resource: "subscription") unless subscription

        render(
          json: ::V2::SubscriptionSerializer.new(
            subscription,
            root_name: "subscription",
            includes: %i[applied_rate_cards]
          )
        )
      end

      # Terminates a subscription in the new engine: ends every product it holds
      # and emits each one's final prorated cycle. Separate from the legacy v1
      # subscription terminate (which bills charges / issues credit notes) — the two
      # engines run side by side.
      def terminate
        subscription = current_organization.subscriptions.find_by(
          external_id: params[:external_id], status: :active
        )
        return not_found_error(resource: "subscription") unless subscription

        result = ::V2::Subscriptions::TerminateService.call(
          subscription:,
          terminated_at: params[:terminated_at] || Time.current
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscription_rate_cards,
              ::V1::SubscriptionRateCardSerializer,
              collection_name: "applied_rate_cards"
            )
          )
        else
          render_error_response(result)
        end
      end

      # Testing helper: fast-forwards one or more product-catalog subscriptions to
      # `timestamp` (default now) and returns what they produced, synchronously. With
      # `terminate: true` it simulates a termination at that date (final prorated cycle +
      # advance credit notes) instead of periodic billing. Takes the id from the path, or
      # an `external_ids` array to bill several at once.
      def bill
        external_ids = Array.wrap(params[:external_ids].presence || params[:external_id])
          .map(&:to_s).reject(&:blank?).uniq
        return not_found_error(resource: "subscription") if external_ids.empty?

        subscriptions = current_organization.subscriptions
          .where(external_id: external_ids, status: :active).to_a
        # Fail on an unknown id rather than silently billing the subset: a typo in a test
        # call should be visible, not look like "that subscription had nothing to bill".
        return not_found_error(resource: "subscription") if subscriptions.size != external_ids.size

        result = ::V2::Subscriptions::BillService.call(
          subscriptions:,
          timestamp: params[:timestamp],
          terminate: ActiveModel::Type::Boolean.new.cast(params[:terminate])
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.invoices, ::V1::InvoiceSerializer, collection_name: "invoices"
            ).serialize.merge(
              ::CollectionSerializer.new(
                result.credit_notes, ::V1::CreditNoteSerializer, collection_name: "credit_notes"
              ).serialize
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def resource_name
        "subscription"
      end
    end
  end
end
