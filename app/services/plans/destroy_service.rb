# frozen_string_literal: true

module Plans
  class DestroyService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless plan.deletable?

      plan.destroy!

      result.plan = plan
      result
    end

    private

    attr_reader :plan
  end
end
