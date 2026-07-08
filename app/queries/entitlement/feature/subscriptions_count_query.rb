# frozen_string_literal: true

module Entitlement
  class Feature
    class SubscriptionsCountQuery < BaseQuery
      Result = BaseResult[:features]
      Filters = BaseFilters[:feature_ids]

      def call
        result = ActiveRecord::Base.connection.exec_query(
          subscriptions_count_query
        )

        result.each_with_object({}) do |row, hash|
          hash[row["entitlement_feature_id"]] = row["count"]
        end
      end

      private

      def subscriptions_count_query
        ActiveRecord::Base.sanitize_sql_array([
          subscriptions_count_sql,
          filters.feature_ids
        ])
      end

      def subscriptions_count_sql
        <<~SQL
          SELECT
            *
          FROM
            entitlement_features_subscriptions_count
          WHERE
            entitlement_feature_id IN (?)
        SQL
      end
    end
  end
end
