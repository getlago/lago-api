# frozen_string_literal: true

module Queries
  class QuotesQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:customer).maybe do
        array(:string, format?: Regex::UUID)
      end
      optional(:status).maybe do
        array(:string, included_in?: Quote::STATUSES.values)
      end
      optional(:number).maybe do
        array(:string, format?: /\AQT-\d{4}-\d{4,}\z/i)
      end
      optional(:version).maybe do
        array(:integer, gt?: 0)
      end
      optional(:from_date).maybe(:date)
      optional(:to_date).maybe(:date)
      optional(:owners).maybe do
        array(:string, format?: Regex::UUID)
      end
    end
  end
end
