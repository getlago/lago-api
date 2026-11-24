# frozen_string_literal: true

# For GraphQL operations that include RequiresSelfServe. The including spec uses "with self-serve enabled" and
# defines `result`, which runs the operation with input that otherwise succeeds.
RSpec.shared_examples "a self-serve entry point" do
  context "when self-serve is off" do
    let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false") }

    it "refuses with self_serve_disabled" do
      expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "self_serve_disabled")
    end
  end
end

# For GraphQL operations that include RequiresSelfServeSignup.
RSpec.shared_examples "a self-serve signup step" do
  it_behaves_like "a self-serve entry point"

  context "when signup is disabled" do
    let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }

    it "refuses with signup_disabled" do
      expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "signup_disabled")
    end
  end

  context "when self-serve is off and signup is disabled" do
    let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false", "LAGO_DISABLE_SIGNUP" => "true") }

    it "refuses with self_serve_disabled" do
      expect(result["errors"].first["extensions"]).to eq("status" => 403, "code" => "self_serve_disabled")
    end
  end
end
