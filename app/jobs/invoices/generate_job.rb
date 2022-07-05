# frozen_string_literal: true

module Invoices
  class GenerateJob < ApplicationJob
    queue_as 'invoices'

    def perform(invoice)
      result = Invoices::GenerateService.new.generate_from_api(invoice)
      result.throw_error unless result.success?
    end
  end
end
