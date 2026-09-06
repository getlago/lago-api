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

      # Testing helper: returns the billing periods that would be generated for
      # active product-catalog subscriptions without creating billing cycles or invoices.
      def cycles
        subscriptions = cycle_subscriptions
        return not_found_error(resource: "subscription") unless subscriptions

        preload_cycle_associations(subscriptions)
        cycles, next_billing_at = cycles_payload_for(subscriptions)
        payload = {cycles:}
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

      def cycle_subscriptions
        return if subscription_external_ids.empty?

        subscriptions = current_organization.subscriptions
          .where(external_id: subscription_external_ids, status: %i[active pending])
          .to_a
        return if subscriptions.size != subscription_external_ids.size

        subscriptions
      end

      def cycles_payload_for(subscriptions)
        cycles = []
        next_billing_ats = []

        subscriptions.each do |subscription|
          subscription_cycles, subscription_next_billing_ats = cycles_for(subscription)
          cycles.concat(subscription_cycles)
          next_billing_ats.concat(subscription_next_billing_ats)
        end

        # The soonest instant anything bills, not the latest: a plan mixing a monthly and a
        # yearly card would otherwise report the yearly one and hide the invoice due next
        # month. LAGO-1792 is explicit that consumers schedule billing runs off this field.
        next_billing_at = cycles.empty? ? nil : next_billing_ats.compact.min

        [cycles, next_billing_at]
      end

      def cycles_for(subscription)
        cycles = []
        next_billing_ats = []
        plan_rate_cards = subscription.plan.applied_rate_cards.to_a

        subscription.applied_rate_cards.each do |subscription_rate_card|
          plan_rate_card = plan_rate_cards.find { it.rate_card_id == subscription_rate_card.rate_card_id }
          build = ::Billing::BuildScheduleService.call(subscription_rate_card:, plan_rate_card:)
          next unless build.success?

          range = cycles_start_at(subscription_rate_card)..cycles_end_at
          rate_phases = rate_phases_for(subscription_rate_card, plan_rate_card:)
          next_billing_ats << build.schedule.next_billing_at(after: range.end)
          cycles.concat(
            previewed_segments(build.schedule, subscription_rate_card, range)
              .map { |segment| serialize_segment(subscription_rate_card, segment, rate_phases) }
          )
        end

        [cycles, next_billing_ats]
      end

      # The preview shows an advance card everything its windows touch, including the cycle
      # in progress, and an arrears card everything that has closed by the end of the range.
      # That asymmetry is the endpoint's own history: the flag it was built on gated advance
      # cards by overlap and arrears cards by their due date, and changing which cycles the
      # preview lists is a product decision, not a port.
      def previewed_segments(schedule, subscription_rate_card, range)
        if subscription_rate_card.rate_card.arrears?
          schedule.segments_due_by(range.end)
        else
          schedule.segments_overlapping(range)
        end
      end

      def preload_cycle_associations(subscriptions)
        ActiveRecord::Associations::Preloader.new(
          records: subscriptions,
          associations: [
            :customer,
            {applied_rate_cards: [:rate_phases, {rate_card: :rates}]},
            {plan: {applied_rate_cards: :rate_phases}}
          ]
        ).call
      end

      def cycles_end_at
        @cycles_end_at ||= if params[:end_on].present?
          params[:end_on].to_date.end_of_day
        else
          Time.current
        end
      end

      def cycles_start_at(subscription_rate_card)
        if params[:start_on].present?
          params[:start_on].to_date.beginning_of_day
        else
          subscription_rate_card.subscription.started_at || subscription_rate_card.started_at
        end
      end

      # The engine hands out phases as overrides, not as identities, so the phase a cycle
      # belongs to is resolved here from its index — the same walk the engine does, on the
      # same list, and the payload has always carried the code.
      def rate_phases_for(subscription_rate_card, plan_rate_card:)
        ::SubscriptionRateCards::ResolveRatePhasesService.call!(
          subscription_rate_card:,
          plan_rate_cards: [plan_rate_card].compact
        ).rate_phases
      end

      def serialize_segment(subscription_rate_card, segment, rate_phases)
        {
          subscription_external_id: subscription_rate_card.subscription.external_id,
          subscription_started_at: subscription_rate_card.subscription.started_at&.iso8601,
          applied_rate_card_id: subscription_rate_card.id,
          applied_rate_card_code: subscription_rate_card.rate_card.code,
          cycle_index: segment.cycle_index + 1, # Display one-based indexes to make QA easier.
          period_from: segment.started_at.iso8601,
          period_to: inclusive_end_of(segment.ended_at).iso8601,
          billing_at: payload_billing_at(subscription_rate_card, segment).iso8601,
          rate_phase_code: rate_phases.rate_phase_for_cycle(segment.cycle_index)&.code,
          rate_override: serialize_rate_override(segment.rate_override),
          rate: serialize_rate(segment),
          rate_code: segment.rate.code
        }
      end

      # The engine's windows are half-open; this payload has always shown the last instant
      # a period covers.
      #
      # This is NOT the only place the two conventions meet, whatever an earlier version of
      # this comment claimed. There are three, with two spellings of the same constant:
      # here, BillingCycles::ScheduleService::PERIOD_END_PRECISION, and
      # SubscriptionRateCards::TerminateService::PERIOD_END_PRECISION. They collapse into one
      # when the billing_segments rename lands; until then, changing one means changing three.
      def inclusive_end_of(ended_at)
        ended_at - Rational(1, 1_000_000)
      end

      # LAGO-1797 pinned this field as "the datetime the cycle actually triggers — period
      # start for advance, period end for arrears". Period end here means the same instant
      # period_to shows, so an arrears trigger is converted alongside it rather than
      # published as the exclusive boundary the engine works in.
      def payload_billing_at(subscription_rate_card, segment)
        return segment.billing_at unless subscription_rate_card.rate_card.arrears?

        inclusive_end_of(segment.billing_at)
      end

      def serialize_rate(segment)
        return if segment.rate_override

        rate = segment.rate

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
