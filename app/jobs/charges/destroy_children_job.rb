# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Charges
  class DestroyChildrenJob < ApplicationJob
    queue_as :default

    def perform(charge_id)
      charge = Charge.with_discarded.find_by(id: charge_id)
      Charges::DestroyChildrenService.call!(charge)
    end
  end
end
