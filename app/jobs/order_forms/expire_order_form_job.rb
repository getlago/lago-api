# frozen_string_literal: true

module OrderForms
  class ExpireOrderFormJob < ApplicationJob
    queue_as :default

    def perform(order_form)
      OrderForms::ExpireService.call!(order_form:)
    end
  end
end
