# frozen_string_literal: true

module Plans
  class PrepareDestroyService < BaseService
    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless plan

      ActiveRecord::Base.transaction do
        plan.update!(pending_deletion: true)
        plan.children.each { |c| c.update!(pending_deletion: true) }
        Plans::DestroyJob.perform_later(plan)
      end

      result.plan = plan
      result
    end

    private

    attr_reader :plan
  end
end
