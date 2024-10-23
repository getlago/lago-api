# frozen_string_literal: true

module Charges
  class UpdateJob < ApplicationJob
    queue_as 'default'

    def perform(charge:, params:, cascade:)
      Charges::UpdateService.call(charge:, params:, cascade:).raise_if_error!
    end
  end
end
