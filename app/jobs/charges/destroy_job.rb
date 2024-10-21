# frozen_string_literal: true

module Charges
  class DestroyJob < ApplicationJob
    queue_as 'default'

    def perform(charge:)
      Charges::DestroyService.call(charge:).raise_if_error!
    end
  end
end
