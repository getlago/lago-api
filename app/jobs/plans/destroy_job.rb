# frozen_string_literal: true

module Plans
  class DestroyJob < ApplicationJob
    queue_as 'default'

    def perform(plan)
      result = Plans::DestroyService.call(plan:)
      result.raise_if_error!
    end
  end
end
