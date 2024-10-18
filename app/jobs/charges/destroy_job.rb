# frozen_string_literal: true

module Charges
  class DestroyJob < ApplicationJob
    queue_as 'default'

    def perform(charge:)
      destroy_result = Charges::DestroyService.call(charge:)
      destroy_result.raise_if_error!
    end
  end
end
