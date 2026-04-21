# frozen_string_literal: true

module Queries
  class QuotesQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:customer).maybe { array(:string, format?: Regex::UUID) }
      optional(:status).maybe do
        value(:string, included_in?: Quote::STATUSES.values) |
          array(:string, included_in?: Quote::STATUSES.values)
      end
      optional(:number).maybe { array(:string, format?: /\AQT-\d{4}-\d{4,}\z/i) }
      optional(:version).maybe { array(:integer, gt?: 0) }
      optional(:from_date).maybe(:date)
      optional(:to_date).maybe(:date)
      optional(:owners).maybe { array(:string, format?: Regex::UUID) }
    end
  end
end
