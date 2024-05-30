# frozen_string_literal: true

module Integrations
  module Aggregator
    module CreditNotes
      class CreateJob < ApplicationJob
        queue_as 'integrations'

        retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 3

        def perform(credit_note:)
          result = Integrations::Aggregator::CreditNotes::CreateService.call(credit_note:)
          result.raise_if_error!
        end
      end
    end
  end
end
