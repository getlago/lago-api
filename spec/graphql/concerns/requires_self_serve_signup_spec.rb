# frozen_string_literal: true

require "rails_helper"

module RequiresSelfServeSignupSpec
  class ThingType < Types::BaseObject
    field :ok, Boolean, null: false
  end

  class GuardedMutation < Mutations::BaseMutation
    include RequiresSelfServeSignup

    graphql_name "GuardedBySelfServeSignup"
    type ThingType

    def resolve(**args)
      context[:calls] << :mutation
      {ok: true}
    end
  end

  class MutationType < Types::BaseObject
    field :guarded, mutation: GuardedMutation
  end

  class TestSchema < LagoApiSchema
    mutation(MutationType)
  end
end

RSpec.describe RequiresSelfServeSignup do
  subject(:result) do
    RequiresSelfServeSignupSpec::TestSchema.execute("mutation { guarded(input: {}) { ok } }", context: {calls:})
  end

  let(:calls) { [] }

  include_context "with self-serve enabled"

  it "runs the mutation" do
    expect(result["data"]["guarded"]).to eq("ok" => true)
    expect(calls).to eq([:mutation])
  end

  it_behaves_like "a self-serve signup step"

  context "when LAGO_DISABLE_SIGNUP is not exactly true" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "TRUE") }

    it "runs the mutation" do
      expect(result["data"]["guarded"]).to eq("ok" => true)
    end
  end

  context "when signup is disabled" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

    it "never runs the mutation" do
      expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "signup_disabled")
      expect(calls).to be_empty
    end
  end
end
