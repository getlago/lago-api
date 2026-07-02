# frozen_string_literal: true

module RatePhases
  # Inserts a phase into its parent's sequence. Positions renumber (later
  # phases shift down); the phase's code is the stable identifier.
  class CreateService < BaseService
    Result = BaseResult[:rate_phase]

    def initialize(plan_rate_card: nil, subscription_rate_card: nil, params: {})
      @plan_rate_card = plan_rate_card
      @subscription_rate_card = subscription_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_phaseable") unless parent

      if plan_locked?
        return result.single_validation_failure!(field: :rate_phase, error_code: "plan_locked")
      end

      existing = parent.rate_phases.order(:position).to_a
      position = (params[:position].presence || default_position(existing)).to_i

      unless position.between?(1, existing.size + 1)
        return result.single_validation_failure!(field: :position, error_code: "non_contiguous_position")
      end

      # Validate the prospective sequence before touching anything: an
      # indefinite phase (null cycle count) is only allowed last.
      counts = existing.map(&:billing_interval_cycle_count).insert(position - 1, params[:billing_interval_cycle_count])
      if counts[0...-1].any?(&:nil?)
        return result.single_validation_failure!(field: :billing_interval_cycle_count, error_code: "non_terminal_indefinite")
      end

      ActiveRecord::Base.transaction do
        # Highest positions first so the unique (parent, position) index never
        # sees a duplicate mid-shift.
        existing.select { |phase| phase.position >= position }.reverse_each do |phase|
          phase.update!(position: phase.position + 1)
        end

        result.rate_phase = RatePhase.create!(
          organization: parent.organization,
          plan_rate_card:,
          subscription_rate_card:,
          code: params[:code].presence,
          position:,
          billing_interval_cycle_count: params[:billing_interval_cycle_count],
          name: params[:name]
        )
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan_rate_card, :subscription_rate_card, :params

    def parent
      plan_rate_card || subscription_rate_card
    end

    def plan_locked?
      plan_rate_card.present? && plan_rate_card.plan.attached_to_subscriptions?
    end

    # Omitted position appends at the end — except a definite phase lands just
    # before an indefinite tail, which must stay terminal.
    def default_position(existing)
      last = existing.last
      if last && last.billing_interval_cycle_count.nil? && params[:billing_interval_cycle_count].present?
        last.position
      else
        existing.size + 1
      end
    end
  end
end
