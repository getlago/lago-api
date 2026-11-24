# frozen_string_literal: true

require "rails_helper"

module RequiresSelfServeSpec
  class ThingType < Types::BaseObject
    field :ok, Boolean, null: false
  end

  class GuardedMutation < Mutations::BaseMutation
    include RequiresSelfServe

    graphql_name "GuardedBySelfServe"
    type ThingType

    def resolve(**args)
      context[:calls] << :mutation
      {ok: true}
    end
  end

  class GuardedResolver < Resolvers::BaseResolver
    include RequiresSelfServe

    type ThingType, null: false

    def resolve
      context[:calls] << :query
      {ok: true}
    end
  end

  class MutationType < Types::BaseObject
    field :guarded, mutation: GuardedMutation
  end

  class QueryType < Types::BaseObject
    field :guarded_thing, resolver: GuardedResolver
  end

  class TestSchema < LagoApiSchema
    query(QueryType)
    mutation(MutationType)
  end
end

RSpec.describe RequiresSelfServe do
  subject(:result) do
    RequiresSelfServeSpec::TestSchema.execute("mutation { guarded(input: {}) { ok } }", context: {calls:})
  end

  let(:calls) { [] }

  include_context "with self-serve enabled"

  it "runs the mutation" do
    expect(result["data"]["guarded"]).to eq("ok" => true)
    expect(calls).to eq([:mutation])
  end

  it_behaves_like "a self-serve entry point"

  context "when self-serve is off" do
    let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false") }

    it "never runs the mutation" do
      expect(result["data"]["guarded"]).to be_nil
      expect(calls).to be_empty
    end
  end

  context "when signup is disabled" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

    it "still runs the mutation" do
      expect(result["data"]["guarded"]).to eq("ok" => true)
    end
  end

  describe "on a query resolver" do
    subject(:result) do
      RequiresSelfServeSpec::TestSchema.execute("query { guardedThing { ok } }", context: {calls:})
    end

    it "runs the query" do
      expect(result["data"]["guardedThing"]).to eq("ok" => true)
    end

    it_behaves_like "a self-serve entry point"
  end
end
