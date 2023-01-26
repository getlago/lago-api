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

      plan.destroy!

      result.plan = plan
      result
    end

    private

    attr_reader :plan
  end
end
