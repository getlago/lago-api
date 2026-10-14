# frozen_string_literal: true

require "rails_helper"

RSpec.describe GraphqlNullByteStripping do
  [GraphQL::Types::String, GraphQL::Types::ID].each do |type|
    describe "#{type.graphql_name}.coerce_input" do
      it "removes null bytes" do
        expect(type.coerce_input("a\u0000b", nil)).to eq("ab")
      end

      it "keeps the text of an escaped null byte" do
        expect(type.coerce_input('a\u0000', nil)).to eq('a\u0000')
      end
    end
  end

  describe "JSON.coerce_input" do
    it "removes null bytes from nested keys and values" do
      value = {"addOns" => [{"localId" => "a\u0000b", "payload" => {"k\u0000" => 1}}]}

      expect(GraphQL::Types::JSON.coerce_input(value, nil)).to eq({"addOns" => [{"localId" => "ab", "payload" => {"k" => 1}}]})
    end
  end

  it "removes null bytes decoded from an inline literal" do
    query = GraphQL.parse('{ customers(searchTerm: "a\\u0000b") { collection { id } } }')
    literal = query.definitions.first.selections.first.arguments.first.value

    expect(literal).to eq("a\u0000b")
    expect(GraphQL::Types::String.coerce_input(literal, nil)).to eq("ab")
  end
end
