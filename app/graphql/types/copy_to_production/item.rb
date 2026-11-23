# frozen_string_literal: true

module Types
  module CopyToProduction
    class Item < Types::BaseObject
      graphql_name "CopyToProductionItem"
      description "A production item created by Copy to production"

      field :code, String, null: true
      field :id, ID, null: false
      field :item_type, Types::CopyToProduction::ItemTypeEnum, null: false
      field :name, String, null: true

      def id
        object.record.id
      end

      def code
        named_record.code
      end

      def name
        named_record.name
      end

      private

      # A plan rate card is known by its rate card.
      def named_record
        object.record.is_a?(PlanRateCard) ? object.record.rate_card : object.record
      end
    end
  end
end
