# frozen_string_literal: true

module OrderForms
  class ExpireOrderFormJob < ApplicationJob
    queue_as :default

    unique :until_executed, on_conflict: :log

    def perform(order_form)
      OrderForms::ExpireService.call!(order_form:)
    end
  end
end
