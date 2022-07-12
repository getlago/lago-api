# frozen_string_literal: true

module Invoices
  class GenerateJob < ApplicationJob
    queue_as 'invoices'

    def perform(invoice)
      Invoices::GenerateService.new.generate_from_api(invoice)
    end
  end
end
