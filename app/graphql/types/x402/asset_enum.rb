# frozen_string_literal: true

module Types
  module X402
    class AssetEnum < Types::BaseEnum
      graphql_name "X402AssetEnum"

      ::X402::Connection::ASSETS.keys.each do |asset|
        value asset
      end
    end
  end
end
