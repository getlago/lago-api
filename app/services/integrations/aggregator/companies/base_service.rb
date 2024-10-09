# frozen_string_literal: true

module Integrations
  module Aggregator
    module Companies
      class BaseService < Integrations::Aggregator::Contacts::BaseService
        def action_path
          "v1/#{provider}/companies"
        end
      end
    end
  end
end
