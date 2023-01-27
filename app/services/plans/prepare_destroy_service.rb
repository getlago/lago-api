# frozen_string_literal: true

module Plans
  class PrepareDestroyService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      plan.update!(pending_deletion: true)
      Plans::DestroyJob.perform_later(plan)

      result.plan = plan
      result
    end

    private

    attr_reader :plan
  end
end
