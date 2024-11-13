# frozen_string_literal: true

module Charges
  class UpdateJob < ApplicationJob
    queue_as 'default'

    def perform(charge:, params:, cascade_options:)
      Charges::UpdateService.call(charge:, params:, cascade_options:).raise_if_error!
    end
  end
end
