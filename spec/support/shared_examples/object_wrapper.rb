# frozen_string_literal: true

# Write action of a native v2 endpoint whose body nests its fields under `key`. The including
# group sends the request as its subject, with `wrapper` as the value of `key`.
RSpec.shared_examples "a v2 action requiring an object wrapper" do |key|
  ["x", ["x"], 1].each do |value|
    context "with a #{value.inspect} #{key} wrapper" do
      let(:wrapper) { value }

      it "returns the missing parameter error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: key.to_s, meta: {}}])
      end
    end
  end
end
