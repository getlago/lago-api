# frozen_string_literal: true

# Turns LAGO_SELF_SERVE_ENABLED on. Nested contexts change the variables through `self_serve_env`:
#
#   let(:self_serve_env) { super().merge("LAGO_DISABLE_SIGNUP" => "true") }
RSpec.shared_context "with self-serve enabled" do
  let(:self_serve_env) { {"LAGO_SELF_SERVE_ENABLED" => "true"} }

  before { stub_const("ENV", ENV.to_h.merge(self_serve_env)) }
end
