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

          # One grouped query instead of one COUNT per row in the serializer.
          applied_rate_cards_counts = SubscriptionRateCard.current_and_scheduled
            .where(subscription_id: subscriptions.map(&:id))
            .group(:subscription_id)
            .count

          render(
            json: ::CollectionSerializer.new(
              subscriptions,
              ::V2::SubscriptionSerializer,
              collection_name: "subscriptions",
              meta: pagination_metadata(subscriptions),
              applied_rate_cards_counts:
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
      # and emits each one's final prorated segment. Separate from the legacy v1
      # subscription terminate (which bills charges / issues credit notes) — the two
      # engines run side by side.
      def terminate
        subscription = current_organization.subscriptions.find_by(
          external_id: params[:external_id], status: :active
        )
        return not_found_error(resource: "subscription") unless subscription

        result = ::V2::Subscriptions::TerminateService.call(
          subscription:,
          terminated_at: termination_time
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscription_rate_cards,
              ::V1::SubscriptionRateCardSerializer,
              collection_name: "applied_rate_cards"
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

      # Testing helper: fast-forwards one or more product-catalog subscriptions to
      # a date range and returns what they produced, synchronously. Takes the id
      # from the path, or an `external_ids` array to bill several at once.
      def bill
        # `subscription_external_ids` is accepted as an alias so the body reads
        # unambiguously; the path form supplies a single `external_id`.
        subscriptions = active_subscriptions
        return not_found_error(resource: "subscription") unless subscriptions
        # Fail on an unknown id rather than silently billing the subset: a typo in a test
        # call should be visible, not look like "that subscription had nothing to bill".

        result = ::V2::Subscriptions::BillService.call(
          subscriptions:,
          start_on: params[:start_on],
          end_on: params[:end_on]
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.invoices,
              ::V1::InvoiceSerializer,
              collection_name: "invoices",
              includes: %i[customer billing_periods subscriptions fees]
            )
          )
        else
          render_error_response(result)
        end
      end

      # Testing helper: returns the billing segments that would be generated for
      # active product-catalog subscriptions without persisting or invoicing any of them.
      def segments
        subscriptions = segment_subscriptions
        return not_found_error(resource: "subscription") unless subscriptions

        preload_segment_associations(subscriptions)
        segments, next_billing_at = segments_payload_for(subscriptions)
        payload = {segments:}
        payload[:next_billing_at] = next_billing_at.iso8601 if next_billing_at

        render json: payload
      end

      private

      def termination_time
        if params[:terminated_at].present?
          Time.zone.parse(params[:terminated_at].to_s)
        else
          Time.current
        end
      end

      def subscription_external_ids
        @subscription_external_ids ||= Array.wrap(
          params[:external_ids].presence ||
            params[:subscription_external_ids].presence ||
            params[:external_id]
        ).map(&:to_s).reject(&:blank?).uniq
      end

      def active_subscriptions_for(external_ids)
        current_organization.subscriptions.where(external_id: external_ids, status: :active).to_a
      end

      def active_subscriptions
        return if subscription_external_ids.empty?

        subscriptions = active_subscriptions_for(subscription_external_ids)
        return if subscriptions.size != subscription_external_ids.size

        subscriptions
      end

      def segment_subscriptions
        return if subscription_external_ids.empty?

        subscriptions = current_organization.subscriptions
          .where(external_id: subscription_external_ids, status: %i[active pending])
          .to_a
        return if subscriptions.size != subscription_external_ids.size

        subscriptions
      end

      def segments_payload_for(subscriptions)
        segments = []
        next_billing_ats = []

        subscriptions.each do |subscription|
          subscription_segments, subscription_next_billing_ats = segments_for(subscription)
          segments.concat(subscription_segments)
          next_billing_ats.concat(subscription_next_billing_ats)
        end

        next_billing_at = segments.empty? ? nil : next_billing_ats.compact.max

        [segments, next_billing_at]
      end

      def segments_for(subscription)
        entries = []
        next_billing_ats = []
        plan_rate_cards = subscription.plan.applied_rate_cards.to_a

        subscription.applied_rate_cards.each do |subscription_rate_card|
          rates = rates_for(subscription_rate_card)
          next if rates.empty?

          build = ::Billing::Schedules::BuildService.call(subscription_rate_card:, plan_rate_cards:)
          next if build.failure?

          next_billing_ats << build.schedule.next_due_at(window_end_at)
          entries.concat(entries_for(subscription_rate_card, build.schedule, rates))
        end

        [entries, next_billing_ats]
      end

      # A cycle is one entry unless a rate changed inside it, in which case each priced
      # window is its own entry — sharing the cycle's index, which is what makes the split
      # visible in the response.
      def entries_for(subscription_rate_card, schedule, rates)
        schedule.cycles_due_by(window_end_at).flat_map do |cycle|
          next [] if cycle.to <= window_start_at(subscription_rate_card)

          ::Billing::Segments.within(cycle.from...cycle.to, rates:).map do |segment|
            serialize_segment(subscription_rate_card, cycle, segment)
          end
        end
      end

      def rates_for(subscription_rate_card)
        subscription_rate_card.rate_card.rates.order(:effective_from)
      end

      def preload_segment_associations(subscriptions)
        ActiveRecord::Associations::Preloader.new(
          records: subscriptions,
          associations: [
            :customer,
            {applied_rate_cards: [:rate_phases, {rate_card: :rates}]},
            {plan: {applied_rate_cards: :rate_phases}}
          ]
        ).call
      end

      def rate_phases_for(subscription_rate_card, plan_rate_cards:)
        ::SubscriptionRateCards::ResolveRatePhasesService.call!(
          subscription_rate_card:,
          plan_rate_cards:
        ).rate_phases
      end

      def window_end_at
        @window_end_at ||= if params[:end_on].present?
          params[:end_on].to_date.end_of_day
        else
          Time.current
        end
      end

      def window_start_at(subscription_rate_card)
        if params[:start_on].present?
          params[:start_on].to_date.beginning_of_day
        else
          subscription_rate_card.subscription.started_at || subscription_rate_card.started_at
        end
      end

      def serialize_segment(subscription_rate_card, cycle, segment)
        {
          subscription_external_id: subscription_rate_card.subscription.external_id,
          subscription_started_at: subscription_rate_card.subscription.started_at&.iso8601,
          applied_rate_card_id: subscription_rate_card.id,
          applied_rate_card_code: subscription_rate_card.rate_card.code,
          cycle_index: cycle.index + 1, # Display one-based indexes to make QA easier.
          period_from: segment.from.iso8601,
          period_to: inclusive_end(segment.to).iso8601,
          billing_at: displayed_billing_at(cycle).iso8601,
          rate_phase_code: cycle.phase.code,
          rate_override: serialize_rate_override(cycle.phase.override),
          rate: serialize_rate(segment.rate, cycle.phase.override),
          rate_code: segment.rate.code
        }
      end

      # Windows are half-open inside the engine and shown inclusive here, so a cycle closing
      # on Aug 17 00:00 reads as ending Aug 16 23:59:59.
      def inclusive_end(instant)
        instant - 1.second
      end

      # An arrears cycle falls due on its closing boundary, shown inclusive like any end; an
      # advance one falls due when it opens, which is a start and shown as it is. A cycle
      # whose moment has passed would be billed on the next run, so it reads as now.
      def displayed_billing_at(cycle)
        due_at = (cycle.due_at == cycle.to) ? inclusive_end(cycle.due_at) : cycle.due_at

        [due_at, Time.current].max
      end

      def serialize_rate(rate, override)
        return if override

        {
          lago_id: rate.id,
          code: rate.code,
          rate_model: rate.rate_model,
          rate_properties: rate.rate_properties,
          billing_interval_count: rate.billing_interval_count,
          billing_interval_unit: rate.billing_interval_unit
        }
      end

      def serialize_rate_override(rate_override)
        return unless rate_override

        {
          lago_id: rate_override.id,
          rate_model: rate_override.rate_model,
          rate_properties: rate_override.rate_properties,
          billing_interval_count: rate_override.billing_interval_count,
          billing_interval_unit: rate_override.billing_interval_unit
        }
      end

      def resource_name
        "subscription"
      end
    end
  end
end
