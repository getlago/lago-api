# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      class CreateJob < ApplicationJob
        queue_as 'integrations'

        unique :until_executed, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100

        def perform(credit_note:)
          result = Integrations::Aggregator::CreditNotes::CreateService.call(credit_note:)
          result.raise_if_error!
        end
      end
    end
  end
end
