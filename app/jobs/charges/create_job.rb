# frozen_string_literal: true

module Charges
  class CreateJob < ApplicationJob
    queue_as 'default'

    def perform(plan:, params:)
      create_result = Charges::CreateService.call(plan:, params:)
      create_result.raise_if_error!
    end
  end
end
