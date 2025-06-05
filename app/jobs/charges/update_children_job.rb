# frozen_string_literal: true

module Charges
  class UpdateChildrenJob < ApplicationJob
    queue_as :default

    def perform(charge:, params:)
      Charges::UpdateChildrenService.call!(charge:, params:)
    end
  end
end
