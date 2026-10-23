# frozen_string_literal: true

module Integrations
  module Aggregator
    class SubsidiariesService < BaseRecordsService
      Result = BaseResult[:subsidiaries]

      Subsidiary = Data.define(:external_id, :external_name)

      def call
        response = fetch_records

        result.subsidiaries = handle_subsidiaries(response["records"])

        result
      end

      private

      def model
        "Subsidiary"
      end

      def handle_subsidiaries(subsidiaries)
        subsidiaries.map do |subsidiary|
          Subsidiary.new(external_id: subsidiary["id"], external_name: subsidiary["name"])
        end
      end
    end
  end
end
