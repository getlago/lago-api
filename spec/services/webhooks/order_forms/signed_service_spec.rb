# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::OrderForms::SignedService do
  subject(:webhook_service) { described_class.new(object: order_form) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "order_form.signed", "order_form", {
      "lago_id" => String,
      "number" => String,
      "status" => "signed",
      "signed_at" => String,
      "lago_quote_id" => String
    }
  end
end
