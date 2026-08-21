# frozen_string_literal: true

module Types
  module Fees
    class Properties < Types::BaseObject
      graphql_name "FeeProperties"

      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      def from_datetime
        if preserve_calendar_date?
          return serialized_calendar_date("from_datetime")
        end

        object.date_boundaries[:from_date]
      end

      def to_datetime
        if preserve_calendar_date?
          return serialized_calendar_date("to_datetime")
        end

        object.date_boundaries[:to_date]
      end

      private

      def preserve_calendar_date?
        context[:invoice_detail] && object.add_on?
      end

      def serialized_calendar_date(property)
        object.properties[property]&.to_date&.to_datetime&.iso8601
      end
    end
  end
end
