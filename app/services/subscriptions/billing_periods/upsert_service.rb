# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Materializes the charges period covering `timestamp` and the one after it, so an event arriving
    # just past a rollover still finds a covering row.
    #
    # Boundaries come from Subscriptions::DatesService, which stays their only source: this service
    # does no date arithmetic beyond probing one second past the current period's end.
    class UpsertService < BaseService
      Result = BaseResult[:periods]

      # A subscription terminated longer ago than this has its final period already stored and
      # nothing left to move, so re-deriving it is wasted work. Matches the window the events
      # processor keeps terminated subscriptions cached for.
      TERMINATED_GRACE_PERIOD = 1.month

      # The subscriptions this service will actually write for, so that a caller fanning out over a
      # scope does not buy a job per subscription that `skip?` refuses. An organization that has been
      # billing for years owns far more subscriptions terminated long ago than it owns live ones.
      def self.maintainable(scope, at: Time.current)
        scope.where(status: :active).or(recently_terminated(scope, at:))
      end

      # The terminated half of `maintainable`, on its own for a caller that only wants those: their
      # final period can still move, and they can still receive backdated events.
      def self.recently_terminated(scope, at: Time.current)
        scope.where(status: :terminated, terminated_at: (at - TERMINATED_GRACE_PERIOD)..)
      end

      def initialize(subscription:, timestamp: Time.current)
        @subscription = subscription
        @timestamp = timestamp

        super
      end

      def call
        result.periods = []
        return result if skip?

        periods = desired_periods

        SubscriptionBillingPeriod.transaction do
          # Every writer takes this, jobs and lifecycle services alike, and holds it until the
          # transaction commits rather than until the end of the block — the outermost transaction,
          # which on a lifecycle path is the whole subscription creation, termination or upgrade.
          #
          # The write is convergent, but the overlap constraint is deferred, so a writer that
          # commits between our delete and our own commit turns that transaction into a constraint
          # violation at COMMIT.
          #
          # Waiting on it costs an open transaction on a pooled connection, so the wait is the
          # short BaseLockService budget and a job that loses the race retries instead.
          Subscriptions::BillingPeriods::LockService.call!(subscription:) do
            # Deleted before the upsert: a customer timezone change snaps period_from to the
            # previous invoice's charges_to (Subscriptions::DatesService#charges_from_datetime), so
            # a moved boundary is a new row rather than an update to the old one, and the two
            # overlap until the old one is gone.
            discarded_periods.delete_all
            reconcile_preceding_period

            if periods.present?
              # Validations are not the guard here: the upsert has to be a single statement so a
              # concurrent writer conflicts on the unique index rather than raising, and the table
              # enforces the ordering, the non-null columns and the non-overlap itself.
              SubscriptionBillingPeriod.upsert_all( # rubocop:disable Rails/SkipsModelValidations
                periods.map { |period| row_for(period) },
                unique_by: %i[scope_id period_from],
                # created_at is left out so a period that is merely refreshed keeps the one it was
                # first written with; Rails bumps updated_at itself.
                update_only: %i[period_to]
              )
            end
          end
        end

        result.periods = periods
        result
      end

      private

      attr_reader :subscription, :timestamp

      def skip?
        return true if subscription.organization.feature_flag_disabled?(:subscription_billing_periods)
        return true if subscription.started_at.nil?
        return true if subscription.plan.interval.nil?
        return true unless subscription.active? || subscription.terminated?
        # Relative to `timestamp` rather than to now, so the periods a service asks for are a
        # function of the moment it asks about.
        return true if subscription.terminated_at.present? &&
          subscription.terminated_at < timestamp - TERMINATED_GRACE_PERIOD

        false
      end

      # A period that opens on or after the discard boundary is the writer's to redraw: the periods
      # being written replace it, and one that is not being written can no longer happen, such as
      # the next period after a termination.
      #
      # A period that opened before the boundary is never dropped: it is closed, and its usage still
      # has to be attributable and billable. It is reconciled onto the new start instead.
      def discarded_periods
        return SubscriptionBillingPeriod.none if discarded_from.nil?

        scope = stored_periods.where(period_from: discarded_from..)

        retained = desired_periods.map(&:period_from)

        # Nothing is being written, so nothing from `discarded_from` onwards is retained. Spelled
        # out rather than left to an empty `period_from NOT IN ()`, which happens to render as true.
        if retained.empty?
          scope
        else
          scope.where.not(period_from: retained)
        end
      end

      # The period that opened before the discard boundary has to end exactly on it. Its own end was
      # derived from the timezone in force when it was written, so a change to that timezone leaves
      # it either overlapping the new start — which the table refuses — or short of it, with the
      # instants in between covered by no period at all.
      #
      # This is where the timezone snap in Subscriptions::DatesService#charges_from_datetime cannot
      # help: it only applies while the previous period is invoiced and within a day of the new
      # start, and neither holds for a period that has yet to be billed.
      def reconcile_preceding_period
        return if discarded_from.nil?

        period = stored_periods.where(period_from: ...discarded_from).order(:period_from).last
        return if period.nil?

        period_to = discarded_from - 1.second
        return if period.period_to < discarded_from && period.period_to >= period_to

        # A period left with nothing to cover is dropped rather than written backwards; the table
        # refuses a period that does not move forward, and there is no usage to key off it.
        if period_to <= period.period_from
          period.delete
        else
          period.update!(period_to:)
        end
      end

      def stored_periods
        SubscriptionBillingPeriod.where(scope_type: "Subscription", scope_id: subscription.id)
      end

      # The termination is a boundary of its own: a subscription terminated at the very instant a
      # period opens has nothing left to store, and the periods stored past that instant still have
      # to go.
      def discarded_from
        return desired_periods.first.period_from if desired_periods.any?

        subscription.terminated_at if subscription.terminated?
      end

      def desired_periods
        @desired_periods ||= begin
          current = build_period(derivation_timestamp)

          if current.nil?
            []
          elsif subscription.terminated?
            # DatesService clamps charges_to to terminated_at, so probing past it repeats the
            # current period instead of yielding the next one.
            #
            # The clamp shortens the final period rather than leaving it at its natural end, which
            # moves the boundary of a row that is already stored. That is safe for a consumer
            # aggregating usage by period: Events::PostProcessService only attaches an event to a
            # terminated subscription while `terminated_at >= event.timestamp`, so the window the
            # clamp removes can never hold usage. The same reason is why the next period goes.
            [current]
          else
            following = build_period(current.period_to + 1.second)
            following = nil unless following && following.period_from > current.period_from

            [current, following].compact
          end
        end
      end

      # A terminated subscription has no period past its termination, so the last one it can have is
      # the one covering `terminated_at`. Deriving it at a later `timestamp` would take the start of
      # the period containing that timestamp while DatesService clamps the end to `terminated_at`,
      # collapsing the period and leaving the subscription with no final period at all.
      def derivation_timestamp
        return timestamp unless subscription.terminated? && subscription.terminated_at.present?

        [timestamp, subscription.terminated_at].min
      end

      def build_period(at)
        dates_service = Subscriptions::DatesService.new_instance(subscription, at, current_usage: true)

        period_from = dates_service.charges_from_datetime
        period_to = dates_service.charges_to_datetime
        return nil if period_from.nil? || period_to.nil?
        # DatesService clamps charges_to to terminated_at, so a subscription terminated at the very
        # instant a period opens — a downgrade taking effect on the billing day, for one — collapses
        # it to nothing. There is no usage to key off it, and the table refuses a period that does
        # not move forward.
        return nil if period_to <= period_from

        Period.new(scope_type: "Subscription", scope_id: subscription.id, period_from:, period_to:)
      end

      def row_for(period)
        {
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          customer_id: subscription.customer_id,
          scope_type: period.scope_type,
          scope_id: period.scope_id,
          period_from: period.period_from,
          period_to: period.period_to
        }
      end
    end
  end
end
