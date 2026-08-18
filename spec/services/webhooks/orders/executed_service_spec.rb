# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Orders::ExecutedService do
  subject(:webhook_service) { described_class.new(object: order) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:order) { create(:order, :executed_in_lago, organization:, customer:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "order.executed", "order", {
      "lago_id" => String,
      "number" => String,
      "status" => "executed",
      "execution_mode" => "execute_in_lago",
      "executed_at" => String,
      "execution_record" => Hash
    }
  end
end
