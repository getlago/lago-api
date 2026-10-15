# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::OrderForms::VoidedService do
  subject(:webhook_service) { described_class.new(object: order_form) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:order_form) { create(:order_form, :voided, organization:, customer:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "order_form.voided", "order_form", {
      "lago_id" => String,
      "number" => String,
      "status" => "voided",
      "void_reason" => "manual",
      "voided_at" => String,
      "lago_quote_id" => String
    }
  end
end
