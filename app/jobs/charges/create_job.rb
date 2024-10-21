# frozen_string_literal: true

module Charges
  class CreateJob < ApplicationJob
    queue_as 'default'

    def perform(plan:, params:)
      Charges::CreateService.call(plan:, params:).raise_if_error!
    end
  end
end
